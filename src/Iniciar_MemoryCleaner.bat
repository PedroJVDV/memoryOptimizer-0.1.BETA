@echo off
title MemoryCleaner Inicializador

echo [INFO] Verificando dependencias do Python...
pip install customtkinter >nul 2>&1

echo [INFO] Iniciando MemoryCleaner Moderno...
start python app.py

exit
