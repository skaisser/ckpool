# CKPool Multi-Node ZMQ Block Notification Enhancement Plan

## Executive Summary

This plan details the modifications needed for the ckpool fork to properly receive ZMQ block notifications from multiple remote BCH nodes. Currently, ckpool only connects to a single ZMQ endpoint (defaults to `tcp://127.0.0.1:28332`), but your production setup requires connecting to multiple remote BCH nodes for redundancy and faster block change detection.

## Current State Analysis

### Existing Architecture
1. **Single ZMQ Connection**: The stratifier process creates one ZMQ subscriber socket connecting to `ckp->zmqblock` (hardcoded default or from config)
2. **Local-Only Design**: The current implementation assumes bitcoind runs on the same server as ckpool
3. **Config Limitation**: The `zmqnotify` field in btcd array entries is parsed but never used
4. **Block Notification Flow**:
   - BCH node publishes block hash via ZMQ
   - Stratifier's `zmqnotify` thread receives the notification
   - Calls `update_base(sdata, GEN_PRIORITY)` to trigger new work generation

### Production Requirements
- Two BCH nodes on separate servers (10.12.112.3 and 10.12.112.4)
- Each node publishes ZMQ notifications on port 28333
- Need redundancy: if one node fails, continue receiving from the other
- Need speed: receive block notifications from whichever node detects it first

## Proposed Solution

### Phase 1: Parse and Store ZMQ Endpoints from Config

**Changes to `src/ckpool.h`:**
```c
// Add to server_instance struct (line ~122)
struct server_instance {
    // ... existing fields ...
    char *zmqnotify;  // Add ZMQ endpoint for this server
};

// Add to ckpool_instance struct (line ~260)
struct ckpool_instance {
    // ... existing fields ...
    char **btcdzmq;      // Array of ZMQ endpoints from btcd servers
    int btcdzmq_count;   // Number of ZMQ endpoints
};
```

**Changes to `src/ckpool.c`:**
```c
// Modify parse_btcds function (~line 1255)
static void parse_btcds(ckpool_t *ckp, const json_t *arr_val, const int arr_size) {
    // ... existing code ...
    ckp->btcdzmq = ckzalloc(sizeof(char *) * arr_size);
    ckp->btcdzmq_count = 0;
    
    for (i = 0; i < arr_size; i++) {
        // ... existing parsing ...
        char *zmqnotify = NULL;
        if (json_get_string(&zmqnotify, val, "zmqnotify")) {
            ckp->btcdzmq[ckp->btcdzmq_count++] = zmqnotify;
            LOGNOTICE("Added ZMQ endpoint %d: %s", i, zmqnotify);
        }
    }
}
```

### Phase 2: Multi-Endpoint ZMQ Subscriber

**Changes to `src/stratifier.c`:**

Replace the single-connection `zmqnotify` function with a multi-connection version:

```c
static void *zmqnotify(void *arg) {
#ifdef HAVE_ZMQ_H
    ckpool_t *ckp = arg;
    sdata_t *sdata = ckp->sdata;
    void *context;
    void **subscribers;
    zmq_pollitem_t *poll_items;
    int num_endpoints, i, rc;
    
    rename_proc("zmqnotify");
    
    // Use btcdzmq endpoints if available, otherwise fall back to single zmqblock
    if (ckp->btcdzmq_count > 0) {
        num_endpoints = ckp->btcdzmq_count;
        LOGNOTICE("Connecting to %d ZMQ endpoints from btcd config", num_endpoints);
    } else if (ckp->zmqblock) {
        num_endpoints = 1;
        LOGNOTICE("Using single ZMQ endpoint: %s", ckp->zmqblock);
    } else {
        LOGERR("No ZMQ endpoints configured");
        goto out;
    }
    
    context = zmq_ctx_new();
    subscribers = ckzalloc(sizeof(void *) * num_endpoints);
    poll_items = ckzalloc(sizeof(zmq_pollitem_t) * num_endpoints);
    
    // Create and connect multiple subscriber sockets
    for (i = 0; i < num_endpoints; i++) {
        const char *endpoint = (ckp->btcdzmq_count > 0) ? 
                               ckp->btcdzmq[i] : ckp->zmqblock;
        
        subscribers[i] = zmq_socket(context, ZMQ_SUB);
        if (!subscribers[i]) {
            LOGERR("zmq_socket failed for endpoint %d with errno %d", i, errno);
            continue;
        }
        
        rc = zmq_setsockopt(subscribers[i], ZMQ_SUBSCRIBE, "hashblock", 0);
        if (rc < 0) {
            LOGERR("zmq_setsockopt failed for endpoint %d with errno %d", i, errno);
            zmq_close(subscribers[i]);
            subscribers[i] = NULL;
            continue;
        }
        
        rc = zmq_connect(subscribers[i], endpoint);
        if (rc < 0) {
            LOGERR("zmq_connect to %s failed with errno %d", endpoint, errno);
            zmq_close(subscribers[i]);
            subscribers[i] = NULL;
            continue;
        }
        
        LOGNOTICE("ZMQ connected to endpoint %d: %s", i, endpoint);
        
        poll_items[i].socket = subscribers[i];
        poll_items[i].events = ZMQ_POLLIN;
    }
    
    // Main polling loop
    while (42) {
        rc = zmq_poll(poll_items, num_endpoints, -1);  // Block indefinitely
        
        if (rc < 0) {
            LOGWARNING("zmq_poll failed with error %d", errno);
            sleep(1);
            continue;
        }
        
        // Check which socket(s) have data
        for (i = 0; i < num_endpoints; i++) {
            if (!subscribers[i])
                continue;
                
            if (poll_items[i].revents & ZMQ_POLLIN) {
                zmq_msg_t message;
                char hexhash[68] = {};
                int size;
                
                do {
                    zmq_msg_init(&message);
                    rc = zmq_msg_recv(&message, subscribers[i], 0);
                    
                    if (rc < 0) {
                        LOGWARNING("zmq_msg_recv from endpoint %d failed with error %d", 
                                  i, errno);
                        zmq_msg_close(&message);
                        break;
                    }
                    
                    size = zmq_msg_size(&message);
                    switch (size) {
                        case 9:
                            LOGDEBUG("ZMQ hashblock message from endpoint %d", i);
                            break;
                        case 4:
                            LOGDEBUG("ZMQ sequence number from endpoint %d", i);
                            break;
                        case 32:
                            update_base(sdata, GEN_PRIORITY);
                            __bin2hex(hexhash, zmq_msg_data(&message), 32);
                            LOGNOTICE("ZMQ block hash %s from endpoint %d", hexhash, i);
                            break;
                        default:
                            LOGWARNING("ZMQ message size error from endpoint %d, size = %d", 
                                      i, size);
                            break;
                    }
                    zmq_msg_close(&message);
                } while (zmq_msg_more(&message));
            }
        }
    }
    
    // Cleanup (never reached in normal operation)
    for (i = 0; i < num_endpoints; i++) {
        if (subscribers[i])
            zmq_close(subscribers[i]);
    }
    free(subscribers);
    free(poll_items);
    zmq_ctx_destroy(context);
    
out:
#endif
    pthread_detach(pthread_self());
    return NULL;
}
```

### Phase 3: Health Monitoring and Reconnection

Add automatic reconnection logic for failed endpoints:

```c
typedef struct zmq_endpoint {
    char *url;
    void *socket;
    time_t last_recv;
    int failures;
    bool connected;
} zmq_endpoint_t;

// Add connection health check every 30 seconds
// Reconnect failed endpoints after 5 second delay
// Log endpoint status for monitoring
```

### Phase 4: Testing Strategy

1. **Unit Testing**:
   - Test config parsing with multiple zmqnotify entries
   - Verify all endpoints are stored correctly

2. **Integration Testing**:
   - Start ckpool with test config pointing to both BCH nodes
   - Verify ZMQ connections to both endpoints
   - Test failover by stopping one BCH node
   - Verify continued operation with single node

3. **Performance Testing**:
   - Measure block notification latency from both nodes
   - Verify no duplicate work generation
   - Test under high block rate (regtest)

## Implementation Steps

### Step 1: Config Parsing (Low Risk)
1. Modify `parse_btcds` to extract and store `zmqnotify` values
2. Add fields to ckpool_instance struct
3. Test config parsing with your production config

### Step 2: Multi-Socket ZMQ (Medium Risk)
1. Implement multi-endpoint zmqnotify function
2. Use zmq_poll for efficient multi-socket handling
3. Test with single endpoint first (backward compatible)
4. Test with multiple endpoints

### Step 3: Production Deployment (Staged)
1. Deploy to test environment with both BCH nodes
2. Monitor logs for successful dual connections
3. Test failover scenarios
4. Deploy to production with careful monitoring

## Configuration Example

Your production config will work as-is:
```json
{
    "btcd": [
        {
            "url": "10.12.112.4:8332",
            "auth": "bchadmin",
            "pass": "sRn6CW1vxKx6GVW5tC5qIMXtg",
            "notify": true,
            "zmqnotify": "tcp://10.12.112.4:28333"
        },
        {
            "url": "10.12.112.3:8332",
            "auth": "bchadmin",
            "pass": "hzxdakoiptYsEjpJHGmrjkiBr",
            "notify": true,
            "zmqnotify": "tcp://10.12.112.3:28333"
        }
    ]
}
```

## Benefits

1. **Redundancy**: Continue operating if one BCH node fails
2. **Lower Latency**: Receive blocks from fastest node
3. **Load Distribution**: RPC calls distributed across nodes
4. **Zero Downtime**: Can maintain/restart nodes individually
5. **Monitoring**: Know which nodes are responsive

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ZMQ library compatibility | Build failures | Test with your exact libzmq version |
| Memory leaks in polling | Resource exhaustion | Careful memory management, valgrind testing |
| Duplicate notifications | Wasted CPU | Deduplicate by block hash |
| Network partitions | Split operation | Monitor both endpoints, alert on divergence |

## Alternative Approaches Considered

1. **External ZMQ Proxy**: Run separate process to aggregate ZMQ and forward to ckpool
   - Pros: No ckpool changes needed
   - Cons: Another component to manage, potential SPOF

2. **HAProxy for ZMQ**: Use HAProxy to load balance ZMQ connections
   - Pros: Battle-tested solution
   - Cons: ZMQ pub/sub doesn't work well with TCP proxies

3. **Modify Notifier Tool**: Change the notifier binary to connect to multiple nodes
   - Pros: Minimal ckpool changes
   - Cons: Still relies on blocknotify, not as fast as direct ZMQ

## Recommendation

Implement the multi-endpoint ZMQ solution (Phases 1-2) as it:
- Provides the best performance (direct ZMQ, no intermediaries)
- Maintains backward compatibility
- Adds minimal complexity to the codebase
- Directly addresses your requirements

The implementation is straightforward and the risk is manageable with proper testing.

## Timeline Estimate

- **Phase 1** (Config parsing): 2-3 hours
- **Phase 2** (Multi-endpoint ZMQ): 4-6 hours  
- **Phase 3** (Health monitoring): 3-4 hours (optional, can be added later)
- **Testing**: 2-3 hours
- **Total**: 8-12 hours for core functionality

## Next Steps

1. Review this plan and provide feedback
2. Set up test environment with two BCH nodes
3. Implement Phase 1 (config parsing)
4. Test and validate config changes
5. Implement Phase 2 (multi-endpoint ZMQ)
6. Comprehensive testing
7. Production deployment with monitoring