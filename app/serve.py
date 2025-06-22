from http.server import HTTPServer, SimpleHTTPRequestHandler
import os

class ImageHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        # Serve the image when root path is requested
        if self.path == '/':
            self.path = 'result.png'  # Change this to your image path
            # Set the correct content type header for the image
            if self.path.lower().endswith('.jpg') or self.path.lower().endswith('.jpeg'):
                self.send_response(200)
                self.send_header('Content-type', 'image/jpeg')
                self.end_headers()
                with open(self.path, 'rb') as f:
                    self.wfile.write(f.read())
                return
            elif self.path.lower().endswith('.png'):
                self.send_response(200)
                self.send_header('Content-type', 'image/png')
                self.end_headers()
                with open(self.path, 'rb') as f:
                    self.wfile.write(f.read())
                return
            # Add other image types as needed
        else:
            # For all other paths, return 404
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'404 Not Found')

# Set the directory containing your image (not strictly needed with absolute paths)
image_path = '/app/result.png'  # Change this to your image path
os.chdir(os.path.dirname(image_path))

port = 8000
server = HTTPServer(('', port), ImageHandler)
print(f"Serving image at http://localhost:{port}/")
server.serve_forever()