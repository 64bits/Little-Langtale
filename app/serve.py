from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
from process import create_furigana_image, load_text

def generate_image():
    """Generate the Japanese text image using functions from process.py"""
    try:
        print("Starting image generation process...")
        
        # Load text (either from test file or AI)
        story_text = load_text().replace('\n***\n', '')
        if story_text is None:
            print("Failed to load text, cannot generate image")
            return False
        
        # Create the image
        print("Creating furigana image...")
        img = create_furigana_image(story_text)
        
        # Save the image
        img.save('result.png')
        print("Image saved as 'result.png'")
        return True
        
    except Exception as e:
        print(f"Error generating image: {e}")
        return False

class ImageHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        # Serve the image when root path is requested
        if self.path == '/':
            print("Generating new image...")
            if not generate_image():
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b'Error generating image')
                return
            
            self.path = 'result.png'
            
            # Set the correct content type header for the image
            self.send_response(200)
            self.send_header('Content-type', 'image/png')
            self.end_headers()
            try:
                with open(self.path, 'rb') as f:
                    self.wfile.write(f.read())
            except FileNotFoundError:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'Image not found')
            return
        else:
            # For all other paths, return 404
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'404 Not Found')

if __name__ == "__main__":
    # Set the directory for serving files
    image_path = '/app/result.png'  # Change this to your image path
    if os.path.dirname(image_path):
        os.chdir(os.path.dirname(image_path))
    
    port = 8000
    server = HTTPServer(('', port), ImageHandler)
    print(f"Serving image at http://localhost:{port}/")
    
    # Generate initial image if it doesn't exist
    if not os.path.exists('result.png'):
        print("Initial image not found, generating...")
        generate_image()
    
    server.serve_forever()