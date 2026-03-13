from __future__ import annotations

import argparse
import json
from typing import Any, Dict, List, Optional, Tuple

try:
    import gradio as gr
except ImportError:
    gr = None

from multimodal_agent import run_agent
 

APP_TITLE = "LG Appliance Multimodal Agent" 
APP_DESCRIPTION = (
    "텍스트, 이미지, 소리를 함께 넣어 가전 증상을 분석하는 멀티모달 진단 챗봇입니다. "
    "오디오 분류 결과와 LG 지원 문서를 근거로 답변합니다."
)


CUSTOM_CSS = """
:root {
  --app-bg: linear-gradient(135deg, #f5efe4 0%, #e8f1ef 45%, #f8faf5 100%);
  --card-bg: rgba(255, 255, 255, 0.88);
  --border-color: rgba(33, 50, 63, 0.12);
  --accent: #0f766e;
  --accent-soft: #d7eeea;
  --ink: #1f2937;
}

.gradio-container {
  background: var(--app-bg);
}

.app-shell {
  max-width: 1180px;
  margin: 0 auto;
}

.hero-card, .panel-card {
  background: var(--card-bg);
  border: 1px solid var(--border-color);
  border-radius: 22px;
  box-shadow: 0 18px 48px rgba(30, 41, 59, 0.08);
}

.hero-card {
  padding: 28px 30px 18px 30px;
  margin-bottom: 18px;
}

.hero-title {
  font-size: 32px;
  font-weight: 800;
  letter-spacing: -0.02em;
  color: var(--ink);
  margin-bottom: 8px;
}

.hero-subtitle {
  color: rgba(31, 41, 55, 0.76);
  font-size: 15px;
  line-height: 1.6;
}

.chip-row {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  margin-top: 16px;
}

.chip {
  background: var(--accent-soft);
  color: var(--accent);
  border-radius: 999px;
  padding: 7px 12px;
  font-size: 12px;
  font-weight: 700;
}
"""


def ensure_gradio() -> None:
    """Raise a readable error if Gradio is not installed."""
    if gr is None:
        raise ImportError("Missing required package: gradio. Install it with `pip install gradio`.")


def build_user_message(user_text: str, image_path: Optional[str], audio_path: Optional[str]) -> str:
    """Format a readable chat bubble for the user message."""
    parts = []
    if user_text.strip():
        parts.append(user_text.strip())
    if image_path:
        parts.append(f"[이미지 첨부: {image_path}]")
    if audio_path:
        parts.append(f"[오디오 첨부: {audio_path}]")
    return "\n".join(parts) if parts else "[입력 없음]"


def build_conversation_context(history: List[Dict[str, str]], current_text: str) -> str:
    """Compress recent turns into a prompt-friendly context string."""
    recent_turns = history[-4:]
    lines = []
    for turn in recent_turns:
        user_text = turn.get("user", "").strip()
        assistant_text = turn.get("assistant", "").strip()
        if user_text:
            lines.append(f"User: {user_text}")
        if assistant_text:
            lines.append(f"Assistant: {assistant_text}")
    if current_text.strip():
        lines.append(f"Current user message: {current_text.strip()}")
    return "\n".join(lines)


def format_evidence(result: Dict[str, Any]) -> Dict[str, Any]:
    """Shape evidence for the JSON panel."""
    return {
        "evidence": result.get("evidence", {}),
    }


def to_chat_messages(history_state: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Convert internal history into the message format expected by Gradio 6."""
    messages: List[Dict[str, str]] = []
    for item in history_state:
        messages.append({"role": "user", "content": item["user"]})
        messages.append({"role": "assistant", "content": item["assistant"]})
    return messages


def chat_once(
    user_text: str,
    image_path: Optional[str],
    audio_path: Optional[str],
    history_state: List[Dict[str, str]],
) -> Tuple[List[Dict[str, str]], List[Dict[str, str]], Dict[str, Any]]:
    """Run one multimodal turn and update chatbot state."""
    history_state = history_state or []

    if not (user_text.strip() or image_path or audio_path):
        message = "텍스트, 이미지, 오디오 중 하나 이상 입력해 주세요."
        return to_chat_messages(history_state), history_state, {"notice": message}

    conversation_text = build_conversation_context(history_state, user_text)
    user_message = build_user_message(user_text, image_path, audio_path)

    try:
        result = run_agent(
            user_text=conversation_text,
            image_path=image_path or None,
            audio_path=audio_path or None,
        )
        assistant_message = result["response"]
        evidence = format_evidence(result)
    except Exception as error:
        assistant_message = (
            "현재 진단 응답 생성 중 오류가 발생했습니다.\n\n"
            f"오류: {error}\n\n"
            "OPENAI_API_KEY, 쿼터 상태, 이미지/오디오 파일 경로를 다시 확인해 주세요."
        )
        evidence = {"error": str(error)}

    history_state = history_state + [{"user": user_message, "assistant": assistant_message}]
    return to_chat_messages(history_state), history_state, evidence


def clear_chat() -> Tuple[List[Dict[str, str]], List[Dict[str, str]], Dict[str, Any], str, None, None]:
    """Reset the full UI state."""
    return [], [], {}, "", None, None


def build_demo() -> "gr.Blocks":
    """Create the Gradio app."""
    ensure_gradio()

    with gr.Blocks(css=CUSTOM_CSS, title=APP_TITLE, theme=gr.themes.Soft()) as demo:
        history_state = gr.State([])

        with gr.Column(elem_classes=["app-shell"]):
            gr.HTML(
                """
                <div class="hero-card">
                  <div class="hero-title">LG Appliance Multimodal Agent</div>
                  <div class="hero-subtitle">
                    텍스트 증상, 제품 이미지, 소리 파일을 함께 입력하면
                    오디오 분류 결과와 LG 공식 지원 문서를 바탕으로 근거 중심 진단을 제공합니다.
                  </div>
                  <div class="chip-row">
                    <div class="chip">Text + Image + Audio</div>
                    <div class="chip">LG Support RAG</div>
                    <div class="chip">Chunk-based Audio Inference</div>
                  </div>
                </div>
                """
            )

            with gr.Row():
                with gr.Column(scale=7, elem_classes=["panel-card"]):
                    chatbot = gr.Chatbot(
                        label="Diagnosis Chat",
                        height=560,
                        show_label=True,
                        layout="bubble",
                    )

                with gr.Column(scale=5, elem_classes=["panel-card"]):
                    symptom_text = gr.Textbox(
                        label="증상 설명",
                        placeholder="예: 냉장고 뒤쪽에서 덜덜거리는 진동 소리가 나고 냉기가 약해진 것 같아요.",
                        lines=6,
                    )
                    image_input = gr.Image(
                        label="제품 이미지",
                        type="filepath",
                        sources=["upload"],
                    )
                    audio_input = gr.Audio(
                        label="소리 파일",
                        type="filepath",
                        sources=["upload", "microphone"],
                    )

                    with gr.Row():
                        submit_btn = gr.Button("진단하기", variant="primary")
                        clear_btn = gr.Button("초기화")

                    evidence_json = gr.JSON(label="Evidence / Debug View")

                    gr.Markdown(
                        """
                        입력 팁
                        - 텍스트: 증상 시점, 에러코드, 냄새/진동 여부
                        - 이미지: 표시창, 설치 상태, 누수/성에/파손 부위
                        - 오디오: 이상 소리가 가장 잘 들리는 3~10초 구간
                        """
                    )

            submit_btn.click(
                fn=chat_once,
                inputs=[symptom_text, image_input, audio_input, history_state],
                outputs=[chatbot, history_state, evidence_json],
            )

            clear_btn.click(
                fn=clear_chat,
                inputs=[],
                outputs=[chatbot, history_state, evidence_json, symptom_text, image_input, audio_input],
            )

    return demo


def main() -> None:
    """CLI entrypoint."""
    ensure_gradio()

    parser = argparse.ArgumentParser(description="Run the multimodal appliance Gradio app.")
    parser.add_argument("--host", default="127.0.0.1", help="Host for the Gradio server")
    parser.add_argument("--port", type=int, default=7860, help="Port for the Gradio server")
    parser.add_argument("--share", action="store_true", help="Enable public Gradio sharing")
    args = parser.parse_args()

    demo = build_demo()
    demo.launch(server_name=args.host, server_port=args.port, share=args.share)


if __name__ == "__main__":
    main()
