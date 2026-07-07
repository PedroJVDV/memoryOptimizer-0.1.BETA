# MemoryCleaner 4.0 🚀

O **MemoryCleaner** é uma ferramenta ultraleve e portátil desenvolvida para Windows, projetada para otimizar sua RAM, limpar o cache inativo (Standby List), e fornecer uma análise profunda sobre a saúde dos seus hardwares (CPU, GPU, Discos e Bateria). 

Com uma interface moderna inspirada em designs *Dark Premium Minimalistas*, ele roda nativamente com chamadas Win32, garantindo zero atraso e precisão extrema.

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11+-blue?style=for-the-badge&logo=python&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## ✨ Novidades da Versão 4.0

- **Análise Inteligente por IA:** A aba de relatórios agora consulta dinamicamente a API aberta do *Pollinations.ai* para fornecer dicas exclusivas sobre como manter a fluidez do seu computador baseado no seu uso atual.
- **Gráficos Neons Complexos:** Integração total com `matplotlib` rodando com temas sombrios, gráficos no estilo "explode", gridlines, e paletas neon de Ciano/Rosa/Roxo.
- **Agendamento Inteligente e Mutuamente Exclusivo:** Configure limpezas automáticas por intervalos de tempo rígidos (ex: a cada 30min) **OU** opte pelo monitoramento silencioso por limiar (ex: quando a RAM passar de 80%). O aplicativo gerencia serviços nativos do Windows.
- **Auto-Elevação:** O software já escala os próprios privilégios para Administrador automaticamente via interface, conseguindo esvaziar os *Working Sets* e limpar o cache fantasma (Standby List) perfeitamente.

## 📥 Como Baixar e Usar (Modo Recomendado)

Este projeto é *Open Source*, mas pensando na facilidade de uso do usuário comum, nós empacotamos **TUDO** em um único executável que não precisa de instalação.

1. Navegue até a raiz deste repositório (ou acesse a aba Releases).
2. Baixe o arquivo **`MemoryCleaner.exe`**.
3. Dê dois cliques para abrir! (Ele pedirá permissões de administrador automaticamente).
4. O programa é 100% portátil. Sem instalações, sem DLLs soltas.

## 🛠️ Para Desenvolvedores (Build)

Se você é desenvolvedor e deseja modificar o código:
1. Clone o repositório.
2. Acesse a pasta `/src/`.
3. Edite o código fonte em Python e PowerShell.
4. Para compilar em um único executável novinho em folha, rode o script `Compilar_App.bat`. O sistema empacotará os temas, dependências (`LibreHardwareMonitorLib.dll`, scripts `.ps1`) e o novo `app.py` num portátil seguro dentro da pasta `/src/dist/`.
