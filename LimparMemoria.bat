@echo off
:: ============================================================
:: MemoryCleaner - Lancador com Privilegios de Administrador
:: Clique duas vezes neste arquivo para abrir o otimizador
:: ============================================================

set "SCRIPT_PATH=%~dp0LimparMemoria.ps1"

:: Verificar se ja esta rodando como admin
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunScript
)

:: Solicitar elevacao via VBScript (metodo mais confiavel)
echo Solicitando permissao de administrador...
set "ELEVATE_VBS=%TEMP%\memorycleaner_elevate.vbs"
echo Set objShell = CreateObject("Shell.Application") > "%ELEVATE_VBS%"
echo objShell.ShellExecute "cmd.exe", "/c """"%~f0""""", "%~dp0", "runas", 1 >> "%ELEVATE_VBS%"
cscript //nologo "%ELEVATE_VBS%"
del "%ELEVATE_VBS%" >nul 2>&1
exit /b

:RunScript
echo Iniciando MemoryCleaner...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
if %errorLevel% neq 0 (
    echo.
    echo [ERRO] Ocorreu um erro ao executar o script.
    echo Pressione qualquer tecla para fechar...
    pause >nul
)
exit /b
