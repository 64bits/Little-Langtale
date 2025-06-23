import re
import os
from PIL import Image, ImageDraw, ImageFont
from dotenv import load_dotenv
import google.generativeai as genai

# Load environment variables from .env file
load_dotenv()

def get_font_path():
    """Get the path to the Noto Sans JP font"""
    # Try different possible font locations
    possible_paths = [
        "/app/fonts/NotoSansJP-Regular.ttf",  # Custom font location
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",  # System install
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.otf",  # Alternative system location
        "NotoSansJP-Regular.ttf",  # Local file
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            print(f"Using font: {path}")
            return path
    
    raise FileNotFoundError("Noto Sans JP font not found. Please ensure it's installed in the Docker container.")

def parse_furigana_text(text):
    # More flexible pattern that allows mixed characters
    pattern = r'([一-龯]+[ぁ-ゟァ-ヿ]*)\[([ぁ-ゟァ-ヿー]+)\]'
    
    segments = []
    last_end = 0
    
    for match in re.finditer(pattern, text):
        # Add any text before this match as regular text
        if match.start() > last_end:
            plain_text = text[last_end:match.start()]
            if plain_text:
                segments.append({'type': 'text', 'content': plain_text})
        
        # Add the text with furigana
        base_text = match.group(1)
        furigana = match.group(2)
        segments.append({
            'type': 'furigana',
            'kanji': base_text,  # Changed from 'kanji' to be more generic
            'reading': furigana
        })
        
        last_end = match.end()
    
    # Add any remaining text
    if last_end < len(text):
        remaining_text = text[last_end:]
        if remaining_text:
            segments.append({'type': 'text', 'content': remaining_text})
    
    return segments

def calculate_segment_width(segment, main_font, furigana_font, draw):
    """Calculate the total width needed for a segment"""
    if segment['type'] == 'text':
        bbox = draw.textbbox((0, 0), segment['content'], font=main_font)
        return bbox[2] - bbox[0]
    else:  # furigana type
        kanji_bbox = draw.textbbox((0, 0), segment['kanji'], font=main_font)
        furigana_bbox = draw.textbbox((0, 0), segment['reading'], font=furigana_font)
        kanji_width = kanji_bbox[2] - kanji_bbox[0]
        furigana_width = furigana_bbox[2] - furigana_bbox[0]
        return max(kanji_width, furigana_width)

def break_text_into_words(segments):
    """Break text segments into individual words/characters for better wrapping"""
    words = []
    
    for segment in segments:
        if segment['type'] == 'text':
            content = segment['content']
            # Split on whitespace for English words, but keep Japanese characters separate
            i = 0
            current_word = ""
            
            while i < len(content):
                char = content[i]
                
                # Handle newlines as explicit line breaks
                if char == '\n':
                    # End current word if we have one
                    if current_word:
                        words.append({'type': 'text', 'content': current_word})
                        current_word = ""
                    # Add newline as line break marker
                    words.append({'type': 'line_break'})
                # Check if character is ASCII (likely English)
                elif ord(char) < 128:
                    if char.isspace():
                        # End current word if we have one
                        if current_word:
                            words.append({'type': 'text', 'content': current_word})
                            current_word = ""
                        # Add space as separate element
                        words.append({'type': 'text', 'content': char})
                    else:
                        # Build English word
                        current_word += char
                else:
                    # End current English word if we have one
                    if current_word:
                        words.append({'type': 'text', 'content': current_word})
                        current_word = ""
                    # Add Japanese character individually for flexible wrapping
                    words.append({'type': 'text', 'content': char})
                
                i += 1
            
            # Add any remaining word
            if current_word:
                words.append({'type': 'text', 'content': current_word})
        else:
            # Keep furigana segments as-is
            words.append(segment)
    
    return words

def can_break_before(word):
    """Determine if we can break a line before this word/character"""
    if word['type'] == 'furigana':
        return True
    
    if word['type'] == 'line_break':
        return True
    
    content = word.get('content', '')
    if not content:
        return True
    
    # Don't break before spaces or punctuation
    if content.isspace():
        return False
    
    # Japanese punctuation that shouldn't start a line
    no_break_start = '。、）】』」！？'
    if content[0] in no_break_start:
        return False
    
    return True

def create_furigana_image(text, width=1264, height=1680, main_size=32, furigana_size=16):
    """Create an 8-bit grayscale image with Japanese text and furigana"""
    
    # Load fonts
    font_path = get_font_path()
    main_font = ImageFont.truetype(font_path, main_size)
    furigana_font = ImageFont.truetype(font_path, furigana_size)
    
    # Create grayscale image (mode 'L' for 8-bit grayscale)
    img = Image.new('L', (width, height), 255)  # 255 = white in grayscale
    draw = ImageDraw.Draw(img)
    
    # Parse the text and break into words
    segments = parse_furigana_text(text)
    words = break_text_into_words(segments)
    
    # Layout parameters
    margin = 50
    line_height = main_size + furigana_size + 10  # Space for furigana above
    max_line_width = width - 2 * margin
    
    x = margin
    y = margin + furigana_size + 5  # Start lower to leave space for furigana
    
    # Group words into lines
    current_line = []
    current_line_width = 0
    
    i = 0
    while i < len(words):
        word = words[i]
        
        # Handle explicit line breaks
        if word['type'] == 'line_break':
            # Draw current line if it has content
            if current_line:
                draw_line(draw, current_line, x, y, main_font, furigana_font, furigana_size)
                current_line = []
                current_line_width = 0
            
            # Move to next line
            y += line_height
            
            # Check if we've run out of vertical space
            if y + main_size > height - margin:
                break
            
            i += 1
            continue
        
        word_width = calculate_segment_width(word, main_font, furigana_font, draw)
        
        # Check if adding this word would exceed line width
        if current_line and current_line_width + word_width + 2 > max_line_width:
            # Try to find a good break point
            if can_break_before(word):
                # Draw current line and start new one
                draw_line(draw, current_line, x, y, main_font, furigana_font, furigana_size)
                y += line_height
                
                # Check if we've run out of vertical space
                if y + main_size > height - margin:
                    break
                
                current_line = [word]
                current_line_width = word_width
            else:
                # Force break even if not ideal
                if current_line:
                    draw_line(draw, current_line, x, y, main_font, furigana_font, furigana_size)
                    y += line_height
                    
                    if y + main_size > height - margin:
                        break
                
                current_line = [word]
                current_line_width = word_width
        else:
            # Add word to current line
            current_line.append(word)
            current_line_width += word_width + 2  # Add small spacing
        
        i += 1
    
    # Draw any remaining line
    if current_line:
        draw_line(draw, current_line, x, y, main_font, furigana_font, furigana_size)
    
    return img

def draw_line(draw, line_words, start_x, y, main_font, furigana_font, furigana_size):
    """Draw a line of words with proper spacing"""
    x = start_x
    
    for word in line_words:
        if word['type'] == 'text':
            # Use 0 for black text in grayscale (0=black, 255=white)
            draw.text((x, y), word['content'], font=main_font, fill=0)
            bbox = draw.textbbox((0, 0), word['content'], font=main_font)
            x += bbox[2] - bbox[0]
        elif word['type'] == 'furigana':  # furigana type
            # Get dimensions
            kanji_bbox = draw.textbbox((0, 0), word['kanji'], font=main_font)
            furigana_bbox = draw.textbbox((0, 0), word['reading'], font=furigana_font)
            kanji_width = kanji_bbox[2] - kanji_bbox[0]
            furigana_width = furigana_bbox[2] - furigana_bbox[0]
            
            # Center furigana above kanji
            kanji_x = x
            furigana_x = x + (kanji_width - furigana_width) / 2
            
            # Draw furigana above (black text)
            draw.text((furigana_x, y - furigana_size + 2.5), word['reading'], 
                     font=furigana_font, fill=0)
            
            # Draw kanji (black text)
            draw.text((kanji_x, y), word['kanji'], font=main_font, fill=0)
            
            x += max(kanji_width, furigana_width)
        
        # Add small space between words (except for spaces which handle their own spacing)
        if not (word['type'] == 'text' and word.get('content', '').isspace()):
            x += 2

def load_text():
    """Load Japanese text based on TEST_MODE environment variable"""
    test_mode = os.getenv('TEST_MODE', 'false').lower() == 'true'
    
    if test_mode:
        # Load from test.txt file
        try:
            with open('test.txt', 'r', encoding='utf-8') as file:
                japanese_text = file.read().strip()
            print("Loaded text from test.txt")
            return japanese_text
        except FileNotFoundError:
            print("Error: test.txt file not found!")
            return None
        except Exception as e:
            print(f"Error reading test.txt: {e}")
            return None
    else:
        # Load from Google Generative AI
        try:
            # Configure the API key
            api_key = os.getenv('GEMINI_API_KEY')
            if not api_key:
                print("Error: GEMINI_API_KEY not found in environment variables!")
                return None
            
            genai.configure(api_key=api_key)
            
            # Create the model
            model = genai.GenerativeModel('gemini-2.5-flash')
            
            # Define the prompt
            prompt = """Generate an intermediate level Japanese paragraph for reading practice. Do not print titles, section markers, or separators. Make it a good story, no more than two paragraphs. For furigana, please place the kana representing the reading in square brackets (私[わたし]) on a per-character basis. Don't apply furigana for a word if there isn't any kanji.
First, print the story in Japanese, with furigana. Then, print the english translation. Separate the translations with three asterisks ***."""
            
            # Generate the content
            print("Generating text from Google Generative AI...")
            response = model.generate_content(prompt)
            
            full_response = response.text
            
            print(f"Generated text from AI (length: {len(full_response)} characters)")
            return full_response
            
        except Exception as e:
            print(f"Error generating text from Google AI: {e}")
            return None

# Example usage
if __name__ == "__main__":
    # Your example text
    japanese_text = load_text().replace('\n***\n', '')

    try:
        # Create the image
        img = create_furigana_image(japanese_text)
        
        # Save as 8-bit grayscale PNG
        img.save('result.png', 'PNG', optimize=True)
        print("8-bit grayscale image saved as 'result.png'")
        
        # Optionally display the image (if running in an environment that supports it)
        # img.show()
    except Exception as e:
        print(f"Error creating image: {e}")
        print("Make sure the Noto Sans JP font is properly installed in your Docker container.")