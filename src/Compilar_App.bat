@echo off
title Compilador MemoryCleaner (.exe)

echo [1/3] Garantindo que os pacotes necessarios estao instalados...
pip install customtkinter pyinstaller >nul 2>&1

echo [2/3] Compilando a Interface Python para MemoryCleaner.exe...
:: --noconsole esconde a tela preta do prompt
:: --onefile cria um unico executavel
:: --name define o nome final
:: --collect-all customtkinter garante que os arquivos de tema da interface vao junto
:: --add-data embute os arquivos auxiliares diretamente dentro do exe
python -m PyInstaller --noconsole --onefile --name MemoryCleaner --collect-all customtkinter --add-data "backend.ps1;." --add-data "LimparSilencioso.ps1;." --add-data "LibreHardwareMonitorLib.dll;." app.py

echo.
echo ====================================================================
echo SUCESSO! APLICATIVO CRIADO.
echo ====================================================================
echo O seu aplicativo "MemoryCleaner.exe" foi gerado na pasta "dist".
echo Ele esta pronto para uso. Basta acessar a pasta dist e abrir o .exe.
echo.
pause
