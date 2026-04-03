@echo off
cd /d "%~dp0..\NNDT-GUI"
if not exist node_modules (
    echo [SNDT] Installing dependencies...
    npm install --silent
)
npx electron .