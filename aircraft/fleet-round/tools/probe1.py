#!/usr/bin/env python3
"""probe1.py PORT PROP : print one property value from the FlightGear telnet props server."""
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=25)
f = s.makefile("rwb", buffering=0)
s.sendall(b"data\r\n")
s.sendall(("get %s\r\n" % sys.argv[2]).encode())
print(f.readline().decode(errors="replace").strip())
s.sendall(b"quit\r\n")
