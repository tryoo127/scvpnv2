#!/usr/bin/env python3
import socket, threading, select, sys, time
from typing import Optional

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv)>1 else 2085

BUFLEN = 16384
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = b'HTTP/1.1 101 OK\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__(daemon=True)
        self.host=host; self.port=port; self.running=False

    def run(self):
        s=socket.socket()
        s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        s.bind((self.host,self.port))
        s.listen(128)
        self.running=True
        print(f"[+] Listening {self.host}:{self.port}", flush=True)
        while self.running:
            try:
                c,a=s.accept()
                ConnectionHandler(c).start()
            except: pass

class ConnectionHandler(threading.Thread):
    def __init__(self, client):
        super().__init__(daemon=True)
        self.client=client
        self.target=None

    def run(self):
        try:
            data=self.client.recv(BUFLEN)
            host=self.get_header(data,'X-Real-Host') or DEFAULT_HOST
            if not host.startswith("127.") and not host.startswith("localhost"):
                self.client.send(b'HTTP/1.1 403\r\n\r\n'); return
            h,p=host.split(":")
            self.target=socket.create_connection((h,int(p)))
            self.client.send(RESPONSE)
            self.forward()
        except Exception as e:
            print("ERR:",e,flush=True)
        finally:
            self.close()

    def get_header(self,data,name):
        try:
            k=(name+": ").encode()
            i=data.find(k)
            if i==-1: return None
            i+=len(k)
            j=data.find(b"\r\n",i)
            return data[i:j].decode()
        except: return None

    def forward(self):
        s=[self.client,self.target]
        while True:
            r,_,_=select.select(s,[],[],3)
            if not r: break
            for x in r:
                d=x.recv(BUFLEN)
                if not d: return
                (self.target if x is self.client else self.client).send(d)

    def close(self):
        for x in [self.client,self.target]:
            try:
                if x: x.close()
            except: pass

if __name__=="__main__":
    Server(LISTENING_ADDR,LISTENING_PORT).start()
    while True: time.sleep(2)
