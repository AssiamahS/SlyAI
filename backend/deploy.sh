#!/bin/bash
# Deploy SlyAI backend to VPS
set -e

VPS="ubuntu@204.236.195.103"
KEY="/Users/djsly/.ssh/slyai-test-key.pem"
SSH="ssh -i $KEY $VPS"

echo "📦 Uploading backend files..."
scp -i $KEY -r /Users/djsly/slyai/backend/server.py /Users/djsly/slyai/backend/requirements.txt $VPS:~/

echo "🔧 Setting up Python environment..."
$SSH "python3 -m venv ~/slyai-env && source ~/slyai-env/bin/activate && pip install -r ~/requirements.txt"

echo "🔑 Setting up API key..."
if [ -n "$1" ]; then
    $SSH "echo 'ANTHROPIC_API_KEY=$1' > ~/.env"
    echo "  API key configured"
else
    echo "  ⚠️  No API key provided. Run: ssh -i $KEY $VPS 'echo ANTHROPIC_API_KEY=sk-ant-xxx > ~/.env'"
fi

echo "🚀 Setting up systemd service..."
$SSH "sudo tee /etc/systemd/system/slyai.service > /dev/null << 'UNIT'
[Unit]
Description=SlyAI Backend API
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
EnvironmentFile=/home/ubuntu/.env
ExecStart=/home/ubuntu/slyai-env/bin/uvicorn server:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT"

$SSH "sudo systemctl daemon-reload && sudo systemctl enable slyai && sudo systemctl restart slyai"

echo "⏳ Waiting for service..."
sleep 3
$SSH "sudo systemctl status slyai --no-pager | head -15"

echo ""
echo "✅ SlyAI backend deployed!"
echo "🌐 API: http://204.236.195.103:8080"
echo "🏥 Health: http://204.236.195.103:8080/health"
