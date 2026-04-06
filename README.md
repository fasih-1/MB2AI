MB2AI is a custom-built, standalone AI desktop application engineered for secure, local network execution. It utilizes a decoupled client-server architecture to bypass aggressive network firewalls, allowing a seamless connection between a sleek graphical interface and a powerful AI backend.

Core Architecture

The Body (Frontend): A native Windows executable compiled with Dart and Flutter. It provides a highly responsive UI, local system notifications, and a custom debug console that streams real-time AI generation logs.

The Brain (Backend): A local-first Python server powered by FastAPI and Uvicorn. It handles web scraping, routes prompts to the Llama API, and communicates with the frontend via loopback (127.0.0.1), ensuring all API traffic can be safely routed through VPN tunnels.

Features

Real-time automated scraping and task fetching.

Dual-mode AI assistance (Tutor Mode & Ghostwriter Mode).

Asynchronous background processing with custom audio-visual task completion alerts.
