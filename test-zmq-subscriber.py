#!/usr/bin/env python3
"""
Test ZMQ subscriber for Bitcoin Cash block notifications
This will connect to the BCH node and show any ZMQ messages received
"""

import sys
import time
import struct
import binascii

try:
    import zmq
except ImportError:
    print("Error: python3-zmq not installed")
    print("Install with: sudo apt-get install -y python3-zmq")
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test-zmq-subscriber.py <node_ip:port>")
        print("Example: python3 test-zmq-subscriber.py 10.0.1.238:28333")
        sys.exit(1)
    
    endpoint = f"tcp://{sys.argv[1]}"
    print(f"Connecting to ZMQ endpoint: {endpoint}")
    
    context = zmq.Context()
    socket = context.socket(zmq.SUB)
    
    # Subscribe to all messages
    socket.setsockopt(zmq.SUBSCRIBE, b"")
    
    try:
        socket.connect(endpoint)
        print("Connected! Waiting for messages...")
        print("(New blocks will appear here when mined)")
        print("-" * 50)
        
        while True:
            try:
                # Receive multipart message
                msg_parts = socket.recv_multipart()
                
                print(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] Received {len(msg_parts)} parts:")
                
                for i, part in enumerate(msg_parts):
                    print(f"Part {i}: ", end="")
                    
                    # Try to decode as string
                    try:
                        decoded = part.decode('utf-8')
                        print(f"'{decoded}'")
                    except:
                        # If not string, show hex
                        print(f"{len(part)} bytes: {binascii.hexlify(part[:32]).decode()}...")
                        
                        # If it's 32 bytes, might be a block hash
                        if len(part) == 32:
                            # Bitcoin hashes are usually displayed reversed
                            hash_hex = binascii.hexlify(part[::-1]).decode()
                            print(f"  Possible block hash: {hash_hex}")
                
            except zmq.Again:
                # No message available (shouldn't happen with blocking recv)
                pass
            except KeyboardInterrupt:
                print("\nStopping...")
                break
            except Exception as e:
                print(f"Error: {e}")
                
    finally:
        socket.close()
        context.term()
        print("Disconnected")

if __name__ == "__main__":
    main()