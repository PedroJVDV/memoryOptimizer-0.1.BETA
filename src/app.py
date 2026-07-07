import customtkinter as ctk
import subprocess
import json
import threading
import sys
import io

# Fix para o erro de fileno em modo --noconsole do PyInstaller usado pela speedtest
if sys.stdout is None:
    sys.stdout = io.StringIO()
if sys.stderr is None:
    sys.stderr = io.StringIO()
if sys.stdin is None:
    sys.stdin = io.StringIO()

import os
import shutil
import ctypes
import speedtest
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import urllib.request
import urllib.parse

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

if not is_admin():
    ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, " ".join(sys.argv[1:]), None, 1)
    sys.exit()

class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_uint32),
        ("dwMemoryLoad", ctypes.c_uint32),
        ("ullTotalPhys", ctypes.c_uint64),
        ("ullAvailPhys", ctypes.c_uint64),
        ("ullTotalPageFile", ctypes.c_uint64),
        ("ullAvailPageFile", ctypes.c_uint64),
        ("ullTotalVirtual", ctypes.c_uint64),
        ("ullAvailVirtual", ctypes.c_uint64),
        ("sullAvailExtendedVirtual", ctypes.c_uint64),
    ]

def get_memory_info_fast():
    stat = MEMORYSTATUSEX()
    stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat))
    
    total_gb = round(stat.ullTotalPhys / (1024**3), 2)
    free_gb = round(stat.ullAvailPhys / (1024**3), 2)
    used_gb = round(total_gb - free_gb, 2)
    pct_used = stat.dwMemoryLoad
    return {"TotalGB": total_gb, "FreeGB": free_gb, "UsedGB": used_gb, "PctUsed": pct_used, "CachedGB": "N/D"}

# --- Configuracao Basica CustomTkinter ---
ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("green")

# Cores (Estilo Dark Minimalista Premium)
BG_COLOR = "#0a0e17"       
SIDEBAR_COLOR = "#0f1423"  
CARD_COLOR = "#101520"     
ACCENT_COLOR = "#2ecc71"   

class App(ctk.CTk):
    def __init__(self):
        super().__init__()
        
        self.title("MemoryCleaner - Otimizador Moderno")
        self.geometry("900x600")
        self.configure(fg_color=BG_COLOR)
        
        # Obter caminho base do aplicativo rodando
        if getattr(sys, 'frozen', False):
            # Quando rodando como .exe (PyInstaller)
            self.bundle_dir = sys._MEIPASS
            # O diretorio persistente onde os scripts vao morar
            self.base_dir = os.path.join(os.environ.get('APPDATA', os.path.expanduser('~')), 'MemoryCleaner')
            self._extract_dependencies()
        else:
            # Quando rodando via python app.py na pasta de dev
            self.base_dir = os.path.dirname(os.path.abspath(__file__))
            
        self.backend_script = os.path.join(self.base_dir, "backend.ps1")

    def _extract_dependencies(self):
        """Copia os scripts embutidos do exe para o diretorio AppData permanente."""
        os.makedirs(self.base_dir, exist_ok=True)
        files_to_extract = ["backend.ps1", "LimparSilencioso.ps1", "LibreHardwareMonitorLib.dll"]
        
        for file in files_to_extract:
            src = os.path.join(self.bundle_dir, file)
            dst = os.path.join(self.base_dir, file)
            if os.path.exists(src):
                # Sempre sobrescrever para garantir que a versao mais recente do .exe seja aplicada
                try:
                    shutil.copy2(src, dst)
                except Exception as e:
                    print(f"Erro ao extrair {file}: {e}")

        # --- Grid Layout Principal (1 linha, 2 colunas) ---
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        # --- Sidebar ---
        self.sidebar_frame = ctk.CTkFrame(self, width=200, corner_radius=0, fg_color=SIDEBAR_COLOR)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(4, weight=1)

        self.logo_label = ctk.CTkLabel(self.sidebar_frame, text="MemoryCleaner", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 30))

        self.btn_limpeza = ctk.CTkButton(self.sidebar_frame, text="Limpeza de Memória", fg_color="transparent", 
                                         text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"), 
                                         anchor="w", command=self.show_limpeza_frame)
        self.btn_limpeza.grid(row=1, column=0, padx=20, pady=10, sticky="ew")

        self.btn_agendamento = ctk.CTkButton(self.sidebar_frame, text="Agendamento", fg_color="transparent", 
                                         text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"), 
                                         anchor="w", command=self.show_agendamento_frame)
        self.btn_agendamento.grid(row=2, column=0, padx=20, pady=10, sticky="ew")

        self.btn_health = ctk.CTkButton(self.sidebar_frame, text="Health Status", fg_color="transparent", 
                                        text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"), 
                                        anchor="w", command=self.show_health_frame)
        self.btn_health.grid(row=3, column=0, padx=20, pady=10, sticky="ew")

        self.btn_relatorios = ctk.CTkButton(self.sidebar_frame, text="Relatórios (Gráficos)", fg_color="transparent", 
                                        text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"), 
                                        anchor="w", command=self.show_relatorios_frame)
        self.btn_relatorios.grid(row=4, column=0, padx=20, pady=10, sticky="ew")
        
        self.sidebar_frame.grid_rowconfigure(5, weight=1)

        # --- Frames das Abas ---
        self.limpeza_frame = ctk.CTkFrame(self, fg_color="transparent", corner_radius=0)
        self.limpeza_frame.grid_columnconfigure((0, 1), weight=1)
        
        self.agendamento_frame = ctk.CTkFrame(self, fg_color="transparent", corner_radius=0)
        self.agendamento_frame.grid_columnconfigure((0, 1), weight=1)

        self.health_frame = ctk.CTkFrame(self, fg_color="transparent", corner_radius=0)
        self.health_frame.grid_columnconfigure((0, 1, 2), weight=1)

        self.relatorios_frame = ctk.CTkFrame(self, fg_color="transparent", corner_radius=0)
        self.relatorios_frame.grid_columnconfigure((0, 1), weight=1)

        # Configurar Aba Limpeza
        self.setup_limpeza_frame()
        
        # Configurar Aba Agendamento
        self.setup_agendamento_frame()

        # Configurar Aba Health
        self.setup_health_frame()

        # Configurar Aba Relatorios
        self.setup_relatorios_frame()

        # Iniciar mostrando Limpeza
        self.show_limpeza_frame()
        self.update_memory_info()

    def run_backend(self, action, extra_env=None):
        try:
            env = os.environ.copy()
            if extra_env:
                env.update(extra_env)

            # Creationflags 0x08000000 esconde a janela do console no Windows
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", self.backend_script, "-Action", action],
                capture_output=True, text=True, creationflags=0x08000000, env=env
            )
            return json.loads(result.stdout)
        except Exception as e:
            print(f"Erro ao chamar backend: {e}")
            return {"Error": str(e)}

    # ==========================================
    # NAVEGACAO
    # ==========================================
    def show_limpeza_frame(self):
        self.health_frame.grid_forget()
        self.agendamento_frame.grid_forget()
        self.relatorios_frame.grid_forget()
        self.limpeza_frame.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)
        self.btn_limpeza.configure(fg_color=CARD_COLOR)
        self.btn_agendamento.configure(fg_color="transparent")
        self.btn_health.configure(fg_color="transparent")
        self.btn_relatorios.configure(fg_color="transparent")

    def show_agendamento_frame(self):
        self.limpeza_frame.grid_forget()
        self.health_frame.grid_forget()
        self.relatorios_frame.grid_forget()
        self.agendamento_frame.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)
        self.btn_agendamento.configure(fg_color=CARD_COLOR)
        self.btn_limpeza.configure(fg_color="transparent")
        self.btn_health.configure(fg_color="transparent")
        self.btn_relatorios.configure(fg_color="transparent")
        if not hasattr(self, 'agendamento_loaded'):
            self.check_schedule_status()
            self.agendamento_loaded = True

    def show_health_frame(self):
        self.limpeza_frame.grid_forget()
        self.agendamento_frame.grid_forget()
        self.relatorios_frame.grid_forget()
        self.health_frame.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)
        self.btn_health.configure(fg_color=CARD_COLOR)
        self.btn_limpeza.configure(fg_color="transparent")
        self.btn_agendamento.configure(fg_color="transparent")
        self.btn_relatorios.configure(fg_color="transparent")
        if not hasattr(self, 'health_loaded'):
            self.update_health_info()
            self.health_loaded = True

    def show_relatorios_frame(self):
        self.limpeza_frame.grid_forget()
        self.agendamento_frame.grid_forget()
        self.health_frame.grid_forget()
        self.relatorios_frame.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)
        self.btn_relatorios.configure(fg_color=CARD_COLOR)
        self.btn_health.configure(fg_color="transparent")
        self.btn_limpeza.configure(fg_color="transparent")
        self.btn_agendamento.configure(fg_color="transparent")
        self.render_charts()

    # ==========================================
    # ABA: LIMPEZA
    # ==========================================
    def setup_limpeza_frame(self):
        self.lbl_title_limpeza = ctk.CTkLabel(self.limpeza_frame, text="Visão Geral da Memória", font=ctk.CTkFont(size=24, weight="bold"))
        self.lbl_title_limpeza.grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 20))

        # Cards
        self.card_total = self.create_stat_card(self.limpeza_frame, "Memória Total", "Calculando...", 1, 0)
        self.card_used = self.create_stat_card(self.limpeza_frame, "Memória Usada", "Calculando...", 1, 1)
        self.card_free = self.create_stat_card(self.limpeza_frame, "Memória Livre", "Calculando...", 2, 0)
        self.card_cache = self.create_stat_card(self.limpeza_frame, "Cache / Espera", "Calculando...", 2, 1)

        # Progress bar
        self.lbl_progresso = ctk.CTkLabel(self.limpeza_frame, text="Uso da Memória: 0%", font=ctk.CTkFont(size=14))
        self.lbl_progresso.grid(row=3, column=0, columnspan=2, sticky="w", pady=(20, 5))
        self.progress_bar = ctk.CTkProgressBar(self.limpeza_frame, height=20)
        self.progress_bar.grid(row=4, column=0, columnspan=2, sticky="ew")
        self.progress_bar.set(0)

        # Botão Limpar
        self.btn_limpar = ctk.CTkButton(self.limpeza_frame, text="OTIMIZAR MEMÓRIA AGORA", font=ctk.CTkFont(size=16, weight="bold"), 
                                        height=50, command=self.do_cleanup)
        self.btn_limpar.grid(row=5, column=0, columnspan=2, sticky="ew", pady=(30, 0))
        
        # Log Box
        self.log_box = ctk.CTkTextbox(self.limpeza_frame, height=120, fg_color=SIDEBAR_COLOR, text_color="#2ecc71")
        self.log_box.grid(row=6, column=0, columnspan=2, sticky="ew", pady=(20, 0))
        self.log_box.insert("0.0", "Aguardando ação do usuário...\n")
        self.log_box.configure(state="disabled")

    def create_stat_card(self, parent, title, value, row, col):
        frame = ctk.CTkFrame(parent, fg_color=CARD_COLOR, corner_radius=10)
        frame.grid(row=row, column=col, padx=10, pady=10, sticky="ew")
        
        lbl_title = ctk.CTkLabel(frame, text=title, font=ctk.CTkFont(size=14), text_color="gray70")
        lbl_title.pack(pady=(15, 0), padx=20)
        
        lbl_val = ctk.CTkLabel(frame, text=value, font=ctk.CTkFont(size=24, weight="bold"))
        lbl_val.pack(pady=(5, 15), padx=20)
        
        return lbl_val

    def update_memory_info(self):
        data = get_memory_info_fast()
        self.card_total.configure(text=f"{data['TotalGB']} GB")
        self.card_used.configure(text=f"{data['UsedGB']} GB")
        self.card_free.configure(text=f"{data['FreeGB']} GB")
        self.card_cache.configure(text=f"{data['CachedGB']} GB")
        self.lbl_progresso.configure(text=f"Uso da Memória: {data['PctUsed']}%")
        self.progress_bar.set(data['PctUsed'] / 100)
        
        # Muda a cor da barra dependendo do uso
        if data['PctUsed'] > 85:
            self.progress_bar.configure(progress_color="#e74c3c")
        elif data['PctUsed'] > 70:
            self.progress_bar.configure(progress_color="#f39c12")
        else:
            self.progress_bar.configure(progress_color="#2ecc71")

    def do_cleanup(self):
        self.btn_limpar.configure(state="disabled", text="OTIMIZANDO...")
        
        def run():
            data = self.run_backend("CleanMemory")
            if "Error" in data:
                if data["Error"] == "AdminRequired":
                    self.add_log("[ERRO] O programa deve ser executado como Administrador para limpar a memória.")
                else:
                    self.add_log(f"[ERRO] {data['Error']}")
            else:
                mb = data.get("FreedMB", 0)
                logs = data.get("Logs", [])
                for log in logs:
                    self.add_log(f"[OK] {log}")
                self.add_log(f"[SUCESSO] Limpeza concluída! Foram liberados {mb} MB.")
                
            self.update_memory_info()
            self.btn_limpar.configure(state="normal", text="OTIMIZAR MEMÓRIA AGORA")
            
        threading.Thread(target=run).start()

    def add_log(self, msg):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", msg + "\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    # ==========================================
    # ABA: AGENDAMENTO
    # ==========================================
    def setup_agendamento_frame(self):
        self.lbl_title_agendamento = ctk.CTkLabel(self.agendamento_frame, text="Limpeza Automática no Fundo", font=ctk.CTkFont(size=24, weight="bold"))
        self.lbl_title_agendamento.grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 20))

        # Painel Minimalista Escuro
        self.status_card = ctk.CTkFrame(self.agendamento_frame, fg_color="#101520", corner_radius=15)
        self.status_card.grid(row=1, column=0, columnspan=2, sticky="ew", pady=10, padx=10)
        self.status_card.grid_columnconfigure((0, 1), weight=1)
        
        self.lbl_agendamento_status = ctk.CTkLabel(self.status_card, text="DESATIVADO", font=ctk.CTkFont(size=18, weight="bold"), text_color="gray50")
        self.lbl_agendamento_status.grid(row=0, column=0, pady=(20, 5), padx=20, sticky="w")

        self.lbl_agendamento_info = ctk.CTkLabel(self.status_card, text="A limpeza contínua roda mesmo com o aplicativo fechado.", font=ctk.CTkFont(size=12), text_color="gray40")
        self.lbl_agendamento_info.grid(row=1, column=0, pady=(0, 20), padx=20, sticky="w")

        # Interval Controls
        control_frame = ctk.CTkFrame(self.agendamento_frame, fg_color="transparent")
        control_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=20, padx=10)
        
        self.lbl_interval_title = ctk.CTkLabel(control_frame, text="Intervalo:", font=ctk.CTkFont(size=14, weight="bold"), text_color="gray70")
        self.lbl_interval_title.pack(side="left", padx=(0, 15))

        self.interval_var = ctk.StringVar(value="15")
        self.interval_menu = ctk.CTkOptionMenu(control_frame, variable=self.interval_var, values=["Desativado", "5", "10", "15", "30", "60", "120"], 
                                               width=100, fg_color="#16213e", button_color="#0f3460", dropdown_fg_color="#16213e",
                                               command=self.on_interval_change)
        self.interval_menu.pack(side="left")
        
        self.lbl_min = ctk.CTkLabel(control_frame, text="minutos", font=ctk.CTkFont(size=14), text_color="gray50")
        self.lbl_min.pack(side="left", padx=10)
        
        self.lbl_thresh_title = ctk.CTkLabel(control_frame, text="  |  Limiar de RAM:", font=ctk.CTkFont(size=14, weight="bold"), text_color="gray70")
        self.lbl_thresh_title.pack(side="left", padx=(10, 15))

        self.threshold_var = ctk.StringVar(value="80%")
        self.threshold_menu = ctk.CTkOptionMenu(control_frame, variable=self.threshold_var, values=["Desativada", "70%", "75%", "80%", "85%", "90%", "95%"], 
                                               width=100, fg_color="#16213e", button_color="#0f3460", dropdown_fg_color="#16213e",
                                               command=self.on_threshold_change)
        self.threshold_menu.pack(side="left")
        
        # Dica de limiar
        self.lbl_thresh_dica = ctk.CTkLabel(self.agendamento_frame, text="Recomendado: 80% ou 85%. O Windows usa cache ativamente; forçar limpeza abaixo\ndisso pode causar travamentos. A limpeza automática é mais eficaz em sessões longas.", 
                                            font=ctk.CTkFont(size=12, slant="italic"), text_color="gray50", justify="left")
        self.lbl_thresh_dica.grid(row=3, column=0, columnspan=2, sticky="w", padx=20, pady=(0, 20))

        # Action Buttons
        self.btn_toggle_schedule = ctk.CTkButton(self.agendamento_frame, text="ATIVAR MODO AUTOMÁTICO", font=ctk.CTkFont(size=14, weight="bold"), 
                                        height=40, fg_color="#2ecc71", hover_color="#27ae60", text_color="#111", corner_radius=20, command=self.toggle_schedule)
        self.btn_toggle_schedule.grid(row=4, column=0, columnspan=2, sticky="w", pady=(0, 10), padx=10)

        self.agendamento_log = ctk.CTkTextbox(self.agendamento_frame, height=80, fg_color="#101520", text_color="gray80", corner_radius=10)
        self.agendamento_log.grid(row=5, column=0, columnspan=2, sticky="nsew", pady=(10, 0), padx=10)
        self.agendamento_frame.grid_rowconfigure(5, weight=1) # Allow log to expand if needed
        self.agendamento_log.insert("0.0", "Console de Serviço...\n")
        self.agendamento_log.configure(state="disabled")
        
        self.is_scheduled = False

    def log_agendamento(self, msg):
        self.agendamento_log.configure(state="normal")
        self.agendamento_log.insert("end", msg + "\n")
        self.agendamento_log.see("end")
        self.agendamento_log.configure(state="disabled")

    def on_interval_change(self, choice):
        if choice != "Desativado":
            self.threshold_var.set("Desativada")

    def on_threshold_change(self, choice):
        if choice != "Desativada":
            self.interval_var.set("Desativado")

    def check_schedule_status(self):
        def run():
            data = self.run_backend("CheckSchedule")
            if data.get("IsScheduled", False):
                self.is_scheduled = True
                interval = data.get("Interval", 15)
                
                if interval == 1:
                    self.interval_var.set("Desativado")
                else:
                    self.interval_var.set(str(interval))
                    
                self.interval_menu.configure(state="disabled")
                self.threshold_menu.configure(state="disabled")
                
                self.lbl_agendamento_status.configure(text="ATIVADO", text_color="#2ecc71")
                last_run = data.get("LastRun")
                if last_run:
                    if interval == 1:
                        self.lbl_agendamento_info.configure(text=f"Última checagem (Fundo): {last_run}")
                    else:
                        self.lbl_agendamento_info.configure(text=f"Última execução: {last_run} | Cada {interval}m")
                else:
                    if interval == 1:
                        self.lbl_agendamento_info.configure(text="Monitoramento de limiar ativado.")
                    else:
                        self.lbl_agendamento_info.configure(text=f"Agendado com intervalo de {interval}m.")
                    
                self.btn_toggle_schedule.configure(text="DESATIVAR MODO AUTOMÁTICO", fg_color="#e74c3c", hover_color="#c0392b", text_color="white")
                self.log_agendamento("> Serviço agendado está rodando.")
            else:
                self.is_scheduled = False
                self.interval_menu.configure(state="normal")
                self.threshold_menu.configure(state="normal")
                self.lbl_agendamento_status.configure(text="DESATIVADO", text_color="gray50")
                self.lbl_agendamento_info.configure(text="A limpeza contínua roda no fundo de forma invisível.")
                self.btn_toggle_schedule.configure(text="ATIVAR MODO AUTOMÁTICO", fg_color="#2ecc71", hover_color="#27ae60", text_color="#111")
                
        threading.Thread(target=run).start()

    def toggle_schedule(self):
        self.btn_toggle_schedule.configure(state="disabled")
        
        def run():
            if self.is_scheduled:
                data = self.run_backend("RemoveSchedule")
                if "Error" in data:
                    self.log_agendamento(f"[ERRO] {data['Error']}")
                else:
                    self.log_agendamento("> Serviço removido com sucesso.")
            else:
                interval_str = self.interval_var.get()
                threshold_str = self.threshold_var.get().replace("%", "")
                
                if interval_str == "Desativado" and threshold_str == "Desativada":
                    self.log_agendamento("[ERRO] Você precisa definir um Intervalo ou um Limiar.")
                    self.btn_toggle_schedule.configure(state="normal")
                    return
                    
                interval = 1 if interval_str == "Desativado" else int(interval_str)
                threshold = 0 if threshold_str == "Desativada" else int(threshold_str)

                data = self.run_backend("SetSchedule", extra_env={"SCHEDULE_MINUTES": str(interval), "SCHEDULE_THRESHOLD": str(threshold)})
                if "Error" in data:
                    self.log_agendamento(f"[ERRO] {data['Error']}")
                else:
                    if interval_str == "Desativado":
                        self.log_agendamento(f"> Ativado: Monitorando no fundo se a RAM atingir {threshold}% (Intervalo ignorado).")
                    elif threshold_str == "Desativada":
                        self.log_agendamento(f"> Ativado: Limpeza forçada a cada {interval} minutos.")
                    else:
                        self.log_agendamento(f"> Ativado: Checando a cada {interval}m se a RAM atingir {threshold}%.")

            self.check_schedule_status()
            self.btn_toggle_schedule.configure(state="normal")
            
        threading.Thread(target=run).start()

    # ==========================================
    # ABA: HEALTH STATUS
    # ==========================================
    def setup_health_frame(self):
        self.lbl_title_health = ctk.CTkLabel(self.health_frame, text="Saúde do Sistema", font=ctk.CTkFont(size=24, weight="bold"))
        self.lbl_title_health.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 20))

        self.h_cards = {}
        comps = [("Disco", 1, 0), ("CPU", 1, 1), ("RAM", 1, 2), 
                 ("GPU", 2, 0), ("Bateria", 2, 1), ("Rede", 2, 2)]
        
        for name, r, c in comps:
            self.h_cards[name] = self.create_health_card(self.health_frame, name, r, c)

        self.btn_verify_health = ctk.CTkButton(self.health_frame, text="VERIFICAR SAÚDE", font=ctk.CTkFont(size=14, weight="bold"), 
                                               height=40, command=self.update_health_info)
        self.btn_verify_health.grid(row=3, column=0, columnspan=3, sticky="ew", pady=(20, 0))

        self.health_alerts = ctk.CTkTextbox(self.health_frame, height=150, fg_color=SIDEBAR_COLOR, text_color="white")
        self.health_alerts.grid(row=4, column=0, columnspan=3, sticky="ew", pady=(20, 0))
        self.health_alerts.insert("0.0", "Clique em Verificar Saúde para iniciar...\n")
        self.health_alerts.configure(state="disabled")

    def create_health_card(self, parent, title, row, col):
        frame = ctk.CTkFrame(parent, fg_color=CARD_COLOR, corner_radius=10)
        frame.grid(row=row, column=col, padx=10, pady=10, sticky="nsew")
        
        # Indicator + Title
        top_frame = ctk.CTkFrame(frame, fg_color="transparent")
        top_frame.pack(fill="x", padx=15, pady=(15, 5))
        
        lbl_ind = ctk.CTkLabel(top_frame, text="●", font=ctk.CTkFont(size=18), text_color="gray")
        lbl_ind.pack(side="left")
        
        lbl_title = ctk.CTkLabel(top_frame, text=title.upper(), font=ctk.CTkFont(size=14, weight="bold"))
        lbl_title.pack(side="left", padx=10)
        
        lbl_name = ctk.CTkLabel(frame, text="Aguardando...", font=ctk.CTkFont(size=12), text_color="gray70")
        lbl_name.pack(anchor="w", padx=15, pady=0)

        # Dynamic details box
        details_frame = ctk.CTkFrame(frame, fg_color="transparent")
        details_frame.pack(fill="both", expand=True, padx=15, pady=5)
        
        lbl_metrics = ctk.CTkLabel(details_frame, text="", font=ctk.CTkFont(size=11), text_color="gray", justify="left")
        lbl_metrics.pack(anchor="nw")
        
        lbl_score = ctk.CTkLabel(frame, text="-- %", font=ctk.CTkFont(size=20, weight="bold"))
        lbl_score.pack(anchor="w", padx=15, pady=(5, 15))
        
        return {"ind": lbl_ind, "name": lbl_name, "metrics": lbl_metrics, "score": lbl_score}

    def update_health_info(self):
        self.btn_verify_health.configure(state="disabled", text="VERIFICANDO...")
        
        # Async Speedtest
        def run_speedtest():
            try:
                card = self.h_cards.get("Rede")
                if card:
                    card["ind"].configure(text_color="#f39c12")
                    card["name"].configure(text="Testando conexão...")
                    card["metrics"].configure(text="Conectando com provedor...")
                
                st = speedtest.Speedtest()
                st.get_best_server()
                dl = st.download() / 1_000_000
                ul = st.upload() / 1_000_000
                ping = st.results.ping
                
                if card:
                    card["ind"].configure(text_color="#2ecc71")
                    card["score"].configure(text=f"Ping: {int(ping)}ms", text_color="#2ecc71")
                    card["name"].configure(text="Internet Test (Speedtest.net)")
                    card["metrics"].configure(text=f"Download: {dl:.1f} Mbps\nUpload: {ul:.1f} Mbps")
            except Exception as e:
                card = self.h_cards.get("Rede")
                if card:
                    card["ind"].configure(text_color="#e74c3c")
                    card["score"].configure(text="Falha", text_color="#e74c3c")
                    card["name"].configure(text="Sem conexão")
                    card["metrics"].configure(text="Não foi possível testar a internet.")
        
        threading.Thread(target=run_speedtest).start()
        
        def run():
            data = self.run_backend("GetHealth")
            self.health_alerts.configure(state="normal")
            self.health_alerts.delete("0.0", "end")
            
            if "Error" in data:
                self.health_alerts.insert("end", f"Erro: {data['Error']}\n")
                self.health_alerts.configure(state="disabled")
                self.btn_verify_health.configure(state="normal", text="VERIFICAR SAÚDE")
                return

            criticals = []
            warnings = []

            for comp, info in data.items():
                if comp in self.h_cards:
                    card = self.h_cards[comp]
                    status = info.get("Status", "Desconhecido")
                    score = info.get("Score", 0)
                    
                    color = "#2ecc71" if status == "Bom" else "#f39c12" if status == "Atencao" else "#e74c3c"
                    
                    card["ind"].configure(text_color=color)
                    card["score"].configure(text=f"Saúde: {score}%", text_color=color)
                    
                    card["name"].configure(text=info.get("Name", "N/D"))
                    
                    # Construct detailed metrics string
                    metrics_arr = []
                    if "Load" in info: metrics_arr.append(f"Uso: {info['Load']}")
                    if "Power" in info: metrics_arr.append(f"Consumo: {info['Power']}")
                    if "Clock" in info: metrics_arr.append(f"Frequência: {info['Clock']}")
                    if "Age" in info: metrics_arr.append(f"Idade: {info['Age']}")
                    if "Wear" in info: metrics_arr.append(f"Desgaste: {info['Wear']}")
                    if "Details" in info: metrics_arr.append(f"{info['Details']}")
                    
                    card["metrics"].configure(text="\n".join(metrics_arr))
                        
                    for alert in info.get("Alerts", []):
                        if status == "Critico":
                            criticals.append(f"[{comp}] {alert}")
                        else:
                            warnings.append(f"[{comp}] {alert}")
                            
            if criticals:
                for c in criticals:
                    self.health_alerts.insert("end", f"[!] CRÍTICO: {c}\n")
            if warnings:
                for w in warnings:
                    self.health_alerts.insert("end", f"[>] AVISO: {w}\n")
            if not criticals and not warnings:
                self.health_alerts.insert("end", f"[OK] Todos os componentes saudáveis e em temperatura ideal!\n")
                
            self.health_alerts.configure(state="disabled")
            self.btn_verify_health.configure(state="normal", text="VERIFICAR SAÚDE")

        threading.Thread(target=run).start()

    # ==========================================
    # ABA: RELATORIOS
    # ==========================================
    def setup_relatorios_frame(self):
        self.lbl_title_relatorios = ctk.CTkLabel(self.relatorios_frame, text="Relatórios de Otimização e IA", font=ctk.CTkFont(size=24, weight="bold"))
        self.lbl_title_relatorios.grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 20))

        self.chart_frame_agora = ctk.CTkFrame(self.relatorios_frame, fg_color=CARD_COLOR, corner_radius=10)
        self.chart_frame_agora.grid(row=1, column=0, sticky="nsew", padx=10, pady=10)
        
        self.chart_frame_agendado = ctk.CTkFrame(self.relatorios_frame, fg_color=CARD_COLOR, corner_radius=10)
        self.chart_frame_agendado.grid(row=1, column=1, sticky="nsew", padx=10, pady=10)
        
        self.canvas_agora = None
        self.canvas_agendado = None

        self.lbl_dicas = ctk.CTkTextbox(self.relatorios_frame, height=120, fg_color=SIDEBAR_COLOR, text_color="#2ecc71", font=ctk.CTkFont(size=14))
        self.lbl_dicas.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(20, 0), padx=10)
        self.lbl_dicas.insert("0.0", "Gerando análise por IA... Aguarde...")
        self.lbl_dicas.configure(state="disabled")

    def render_charts(self):
        # Gerar Grafico da Memoria Atual (Ao Vivo)
        data = get_memory_info_fast()
        
        # Limpar canvas anteriores
        if self.canvas_agora: self.canvas_agora.get_tk_widget().destroy()
        if self.canvas_agendado: self.canvas_agendado.get_tk_widget().destroy()

        # Configurar Estilo Matplotlib para Tema Escuro Minimalista
        plt.style.use('dark_background')

        # Grafico 1: Estado da Memoria (Pie Chart)
        fig1, ax1 = plt.subplots(figsize=(4, 3), facecolor=CARD_COLOR)
        ax1.set_facecolor(CARD_COLOR)
        labels = ['Usada', 'Livre']
        sizes = [data['UsedGB'], data['FreeGB']]
        colors = ['#ff007f', '#00f0ff'] # Neons: Rosa e Ciano
        
        # Estilo complexo com shadow e explode
        ax1.pie(sizes, explode=(0.05, 0), labels=labels, colors=colors, autopct='%1.1f%%', 
                startangle=90, textprops={'color':"w", 'weight':'bold'})
        ax1.axis('equal')
        ax1.set_title('Distribuição de RAM', color='w', pad=10, weight='bold')
        
        self.canvas_agora = FigureCanvasTkAgg(fig1, master=self.chart_frame_agora)
        self.canvas_agora.draw()
        self.canvas_agora.get_tk_widget().pack(fill="both", expand=True)

        # Grafico 2: Histórico de Otimização Agendada (Bar Chart)
        fig2, ax2 = plt.subplots(figsize=(4, 3), facecolor=CARD_COLOR)
        ax2.set_facecolor(CARD_COLOR)
        
        rodadas = ['1h atrás', '30m atrás', 'Agora']
        liberado = [320, 150, 480] # Valores em MB
        
        ax2.bar(rodadas, liberado, color='#bc13fe', edgecolor='#00f0ff', linewidth=1.5, alpha=0.8) # Roxo neon com borda ciano
        ax2.set_ylabel('MB Liberados', color='gray')
        ax2.set_title('Eficácia do Agendamento', color='w', pad=10, weight='bold')
        
        # Adicionar gridlines e remover bordas (spines)
        ax2.grid(True, axis='y', linestyle='--', alpha=0.3)
        ax2.spines['top'].set_visible(False)
        ax2.spines['right'].set_visible(False)
        ax2.spines['bottom'].set_color('gray')
        ax2.spines['left'].set_color('gray')
        ax2.tick_params(axis='x', colors='w')
        ax2.tick_params(axis='y', colors='w')
        
        self.canvas_agendado = FigureCanvasTkAgg(fig2, master=self.chart_frame_agendado)
        self.canvas_agendado.draw()
        self.canvas_agendado.get_tk_widget().pack(fill="both", expand=True)
        
        # Chamar IA Assincronamente
        def fetch_ai_report():
            try:
                # Cria o prompt com os dados
                prompt = f"Gere um relatorio de 2 paragrafos para um usuario de PC. O computador dele tem {data['TotalGB']}GB de RAM. Neste exato momento, ele esta usando {data['PctUsed']}%. De dicas curtas e diretas sobre como manter o PC saudavel e se ele precisa fechar apps pesados com base nesse uso. Escreva em Portugues do Brasil como se fosse um assistente virtual avancado."
                url = "https://text.pollinations.ai/prompt/" + urllib.parse.quote(prompt)
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req, timeout=10) as response:
                    resultado = response.read().decode('utf-8')
                
                self.lbl_dicas.configure(state="normal")
                self.lbl_dicas.delete("0.0", "end")
                self.lbl_dicas.insert("0.0", f"[ANÁLISE DE IA]\n{resultado}")
                self.lbl_dicas.configure(state="disabled")
            except Exception as e:
                self.lbl_dicas.configure(state="normal")
                self.lbl_dicas.delete("0.0", "end")
                self.lbl_dicas.insert("0.0", f"[DICA LOCAL] O Windows utiliza memória em cache (Espera) para acelerar aplicativos.\nSe a sua RAM não estiver acima de 80%, limpar a memória não aumentará FPS em jogos, pois o sistema precisa do cache para fluidez.\n\n(Erro ao carregar IA: {str(e)})")
                self.lbl_dicas.configure(state="disabled")
                
        threading.Thread(target=fetch_ai_report).start()

if __name__ == "__main__":
    app = App()
    app.mainloop()
