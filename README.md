# MemoryOptimizer 0.1 BETA

**Otimizador de memoria nativo para Windows 11** — Ferramenta leve que limpa cache, libera RAM e gerencia servicos desnecessarios com interface grafica escura e moderna.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![Version](https://img.shields.io/badge/Version-0.1%20BETA-orange?style=for-the-badge)

---

## Sobre o Projeto

O **MemoryOptimizer** foi criado para resolver um problema comum no Windows 11: **o uso excessivo de RAM por cache e servicos em segundo plano**. Muitos usuarios notam que o sistema consome 60-80% da memoria mesmo sem programas abertos, e esta ferramenta ataca diretamente as causas desse consumo.

### O que o Windows faz com sua RAM?

O Windows 11 utiliza agressivamente a RAM para:
- **Standby Cache**: Armazena dados de programas que voce ja fechou, "caso precise de novo"
- **Servicos em segundo plano**: Dezenas de servicos rodam automaticamente (telemetria, Xbox, indexacao, etc.)
- **Working Sets inflados**: Processos reservam mais memoria do que realmente precisam

O MemoryOptimizer age diretamente nessas tres frentes.

---

## Funcionalidades

### Limpeza de Memoria
| Funcao | Descricao |
|--------|-----------|
| **Flush Working Sets** | Reduz o working set de todos os processos ativos, liberando RAM que foi reservada mas nao esta em uso |
| **Clear Standby Cache** | Limpa a Standby List do Windows (memoria "em espera") usando a API `NtSetSystemInformation` |
| **Clear Modified Pages** | Libera paginas de memoria modificadas que estao pendentes de gravacao em disco |
| **Garbage Collection .NET** | Forca a coleta de lixo do runtime .NET, liberando objetos nao referenciados |
| **Limpeza de Temporarios** | Remove arquivos temporarios com mais de 1 hora das pastas TEMP do sistema e do usuario |
| **Flush DNS Cache** | Limpa o cache de resolucao DNS do sistema |

### Gerenciamento de Servicos

A ferramenta identifica automaticamente ate **25 servicos** do Windows que sao comumente desnecessarios e mostra seu status em tempo real:

| Categoria | Servicos |
|-----------|----------|
| **Telemetria** | DiagTrack, dmwappushservice, WerSvc |
| **Xbox** | XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc |
| **Indexacao** | WSearch (Windows Search), SysMain (Superfetch) |
| **Comunicacao** | PhoneSvc, Fax, icssvc (Hotspot) |
| **Outros** | MapsBroker, lfsvc, RetailDemo, wisvc, WbioSrvc, WMPNetworkSvc, RemoteRegistry, TrkWks, PcaSvc, AJRouter, BDESVC, TabletInputService |

> **Nota:** Voce escolhe quais servicos desativar marcando as caixas de selecao. Nenhum servico e parado automaticamente sem sua autorizacao.

### Interface Grafica

- **Dark theme** moderno com paleta de cores cuidadosamente selecionada
- **4 cards informativos**: Total, Em Uso, Livre e Cache — atualizados em tempo real
- **Barra de progresso** colorida: verde (<60%), laranja (60-80%), vermelho (>80%)
- **Lista de servicos** com checkboxes e indicadores de status
- **Log em tempo real** mostrando cada etapa da otimizacao
- **Efeitos de hover** nos botoes para feedback visual

---

## Como Usar

### Requisitos
- **Windows 10/11** (64-bit)
- **PowerShell 5.1+** (ja incluso no Windows)
- **Permissao de Administrador** (solicitada automaticamente)

### Instalacao

1. **Clone o repositorio:**
```bash
git clone https://github.com/PedroJVDV/memoryOptimizer-0.1.BETA.git
```

2. **Ou baixe diretamente:**
   - Clique em **Code > Download ZIP** no GitHub
   - Extraia em qualquer pasta

### Execucao

1. **Clique duas vezes** em `LimparMemoria.bat`
2. **Aceite o UAC** (prompt de permissao de administrador)
3. A interface grafica abrira mostrando o uso atual de memoria
4. **(Opcional)** Marque os servicos que deseja desativar na lista
5. Clique em **LIMPAR MEMORIA**
6. Acompanhe o progresso no log em tempo real

> **Dica:** Use o botao **ATUALIZAR** para ver os valores de memoria atualizados apos a limpeza.

---

## Arquitetura Tecnica

### Estrutura de Arquivos

```
MemoryOptimizer/
|-- LimparMemoria.bat    # Lancador com elevacao de privilegios
|-- LimparMemoria.ps1    # Script principal (GUI + logica)
|-- README.md            # Este arquivo
```

### Como Funciona

O script utiliza **P/Invoke** para chamar APIs nativas do Windows diretamente do PowerShell:

```
PowerShell Script
    |
    |-- [System.Windows.Forms]  ->  Interface Grafica (WinForms)
    |
    |-- [psapi.dll]
    |     |-- EmptyWorkingSet()  ->  Reduz working set por processo
    |
    |-- [ntdll.dll]
    |     |-- NtSetSystemInformation()
    |           |-- Command 4: Purge Standby List (limpa cache)
    |           |-- Command 3: Flush Modified List
    |
    |-- [advapi32.dll]
    |     |-- OpenProcessToken()
    |     |-- AdjustTokenPrivileges()  ->  Eleva privilegios para manipular memoria
    |     |-- LookupPrivilegeValue()
    |
    |-- [kernel32.dll]
          |-- CloseHandle()  ->  Libera handles do sistema
```

### Fluxo de Elevacao

```
Usuario clica no .bat
    |
    v
Verifica admin? --[NAO]--> Cria VBScript temporario
    |                           |
   [SIM]                        v
    |                    ShellExecute com "runas"
    v                           |
Executa PowerShell              v
com -ExecutionPolicy        Prompt UAC
Bypass                          |
    |                           v
    v                    Re-executa .bat como admin
Interface abre                  |
                                v
                           Executa PowerShell
                                |
                                v
                           Interface abre
```

### APIs do Windows Utilizadas

| DLL | Funcao | Finalidade |
|-----|--------|-----------|
| `psapi.dll` | `EmptyWorkingSet` | Forca a reducao do working set de um processo, devolvendo paginas ao sistema |
| `ntdll.dll` | `NtSetSystemInformation` | API nao documentada que permite manipular a Memory List do kernel (standby, modified) |
| `advapi32.dll` | `AdjustTokenPrivileges` | Eleva os privilegios `SeProfileSingleProcessPrivilege` e `SeIncreaseQuotaPrivilege` necessarios para a limpeza |
| `kernel32.dll` | `CloseHandle` | Libera handles apos uso para evitar vazamento de recursos |

---

## Perguntas Frequentes

### E seguro usar?

**Sim.** A ferramenta utiliza as mesmas APIs que o proprio Windows usa internamente. A limpeza de cache nao apaga dados permanentes — apenas libera paginas de memoria que o Windows estava guardando "por conveniencia". Apos a limpeza, se o Windows precisar daqueles dados novamente, ele simplesmente os recarrega do disco.

### Vou perder dados?

**Nao.** Nenhum arquivo pessoal e afetado. A limpeza de temporarios so remove arquivos com mais de 1 hora na pasta TEMP. Os servicos parados podem ser reiniciados a qualquer momento pelo `services.msc`.

### Posso usar com frequencia?

Sim, voce pode executar a ferramenta sempre que sentir que o PC esta lento. Nao ha limite de uso. Porem, o Windows vai naturalmente preencher o cache novamente apos algum tempo — isso e comportamento normal.

### Um servico que eu parei era importante, como reverter?

1. Pressione `Win + R`
2. Digite `services.msc` e pressione Enter
3. Encontre o servico na lista
4. Clique com botao direito > **Propriedades**
5. Mude o Tipo de inicializacao para **Automatico**
6. Clique em **Iniciar**

### O programa precisa de internet?

**Nao.** Tudo roda 100% offline e localmente. Nenhum dado e enviado para nenhum servidor.

---

## Avisos Importantes

> **ATENCAO:** Esta e uma versao BETA. Embora a ferramenta seja segura para uso geral, recomenda-se cautela ao desativar servicos. Desativar o servico errado pode afetar funcionalidades especificas do Windows (ex: desativar o WSearch desliga a busca do menu Iniciar).

> **SERVICOS DO XBOX:** Se voce joga jogos da Microsoft Store ou usa o Xbox Game Pass, **nao desative** os servicos Xbox.

> **WINDOWS UPDATE:** O servico `wuauserv` (Windows Update) esta listado mas deve ser parado apenas temporariamente se voce sabe o que esta fazendo. O Windows vai reinicia-lo automaticamente.

---

## Roadmap (Proximas Versoes)

- [ ] Salvar configuracoes de servicos em arquivo de perfil
- [ ] Agendamento automatico de limpeza (Task Scheduler)
- [ ] Monitoramento em tempo real com graficos
- [ ] Deteccao automatica de processos com alto consumo de RAM
- [ ] Modo "Gaming" que otimiza para jogos
- [ ] Exportar relatorio de otimizacao em TXT/HTML
- [ ] Suporte a temas (claro/escuro)

---

## Contribuindo

Contribuicoes sao bem-vindas! Para contribuir:

1. Faca um **Fork** do projeto
2. Crie uma branch para sua feature (`git checkout -b feature/minha-feature`)
3. Commit suas mudancas (`git commit -m 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/minha-feature`)
5. Abra um **Pull Request**

---

## Licenca

Este projeto esta licenciado sob a **MIT License** — veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## Autor

Desenvolvido por **PedroJVDV** 

---

<p align="center">
  <b>Se este projeto te ajudou, deixe uma estrela no repositorio!</b>
</p>
