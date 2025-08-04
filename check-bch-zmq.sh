#!/bin/bash

echo "Run this on your BCH node (10.0.1.238)"
echo "======================================="
echo

echo "1. Check if ZMQ is enabled in bitcoin.conf:"
grep -i zmq ~/.bitcoin/bitcoin.conf

echo
echo "2. Check if bitcoind is listening on port 28333:"
sudo netstat -tlnp | grep 28333
echo "or"
ss -tln | grep 28333

echo
echo "3. Check bitcoind ZMQ settings:"
bitcoin-cli getzmqnotifications

echo
echo "4. Check firewall rules:"
sudo ufw status | grep -E "28333|8332"

echo
echo "5. Check recent bitcoind logs for ZMQ:"
tail -100 ~/.bitcoin/debug.log | grep -i zmq | tail -10

echo
echo "If ZMQ is not enabled, add to bitcoin.conf:"
echo "zmqpubhashblock=tcp://0.0.0.0:28333"
echo "Then restart bitcoind"