import flet as ft
import os
from llama_cpp import Llama
import threading
import time

# Global variable for the model
llm = None
model_path = "/home/aadhityan/Downloads/llama32-1b-qlora-exam_q4_k_m.gguf"

def main(page: ft.Page):
    page.title = "Offline LLM Chat"
    page.theme_mode = ft.ThemeMode.DARK
    page.padding = 20

    # Chat messages list
    chat_list = ft.ListView(
        expand=True,
        spacing=10,
        auto_scroll=True,
    )

    # Input field
    user_input = ft.TextField(
        hint_text="Type your message here...",
        expand=True,
        border_color=ft.colors.BLUE_400,
        multiline=True,
        shift_enter=True,
    )

    # Status text
    status_text = ft.Text("Ready", size=12, color=ft.colors.GREY_400)

    def add_message(role, text):
        align = ft.MainAxisAlignment.END if role == "user" else ft.MainAxisAlignment.START
        bg_color = ft.colors.BLUE_900 if role == "user" else ft.colors.GREY_800
        
        chat_list.controls.append(
            ft.Row(
                [
                    ft.Container(
                        content=ft.Text(text, selectable=True),
                        padding=10,
                        border_radius=10,
                        bgcolor=bg_color,
                        width=min(400, page.window.width * 0.8), # Responsive width
                    )
                ],
                alignment=align,
            )
        )
        page.update()

    def load_model():
        global llm
        status_text.value = f"Loading model from {model_path}..."
        page.update()
        
        if not os.path.exists(model_path):
            status_text.value = f"Error: Model not found at {model_path}"
            add_message("system", f"Model file not found: {model_path}\nPlease place the .gguf file there or update the path.")
            page.update()
            return

        try:
            # Initialize Llama model
            # n_ctx=2048 is context window, adjust as needed
            llm = Llama(model_path=model_path, n_ctx=2048, verbose=False)
            status_text.value = "Model loaded successfully!"
        except Exception as e:
            status_text.value = f"Error loading model: {str(e)}"
            add_message("system", f"Failed to load model: {str(e)}")
        
        page.update()

    def send_message(e):
        if not user_input.value:
            return
        
        prompt = user_input.value
        user_input.value = ""
        user_input.disabled = True
        send_button.disabled = True
        
        add_message("user", prompt)
        status_text.value = "Generating response..."
        page.update()

        def generate():
            global llm
            if llm is None:
                # Try loading if not loaded
                load_model()
                if llm is None:
                    user_input.disabled = False
                    send_button.disabled = False
                    page.update()
                    return

            try:
                # Simple prompt format - can be improved based on model template
                # For Llama 3, usually: <|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n{prompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n
                # But raw prompt often works for simple tests.
                
                formatted_prompt = f"User: {prompt}\nAssistant: "
                
                output = llm(
                    formatted_prompt, 
                    max_tokens=512, 
                    stop=["User:", "\nUser"], 
                    echo=False
                )
                
                response_text = output['choices'][0]['text']
                add_message("assistant", response_text)
                status_text.value = "Ready"
                
            except Exception as ex:
                add_message("system", f"Error generating: {str(ex)}")
                status_text.value = "Error"

            user_input.disabled = False
            send_button.disabled = False
            user_input.focus()
            page.update()

        # Run generation in a separate thread
        threading.Thread(target=generate, daemon=True).start()

    send_button = ft.IconButton(
        icon=ft.icons.SEND,
        icon_color=ft.colors.BLUE_400,
        on_click=send_message
    )

    # Layout
    page.add(
        ft.Container(
            content=chat_list,
            expand=True,
            padding=10,
        ),
        ft.Container(
            content=ft.Column([
                status_text,
                ft.Row([user_input, send_button], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
            ]),
            padding=10,
            bgcolor=ft.colors.GREY_900,
            border_radius=ft.border_radius.only(top_left=10, top_right=10)
        )
    )
    
    # Initial load
    threading.Thread(target=load_model, daemon=True).start()

if __name__ == "__main__":
    ft.app(target=main)
