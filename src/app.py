import customtkinter as ctk
import subprocess
import json
import threading
import sys
import io
import os
import shutil
import ctypes

# Fix para o erro de fileno em modo --noconsole do PyInstaller
if sys.stdout is None:
    sys.stdout = io.StringIO()
if sys.stderr is None:
    sys.stderr = io.StringIO()
if sys.stdin is None:
    sys.stdin = io.StringIO()

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
            self.bundle_dir = sys._MEIPASS
            self.base_dir = os.path.join(os.environ.get('APPDATA', os.path.expanduser('~')), 'MemoryCleaner')
            self._extract_dependencies()
        else:
            self.base_dir = os.path.dirname(os.path.abspath(__file__))
            
        self.backend_script = os.path.join(self.base_dir, "backend.ps1")

        # --- Grid Layout Principal (1 linha, 2 colunas) ---
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        # --- Sidebar ---
        self.sidebar_frame = ctk.CTkFrame(self, width=200, corner_radius=0, fg_color=SIDEBAR_COLOR)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(2, weight=1)

        self.logo_label = ctk.CTkLabel(self.sidebar_frame, text="MemoryCleaner", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 30))

        self.btn_limpeza = ctk.CTkButton(self.sidebar_frame, text="Limpeza de Memória", fg_color=CARD_COLOR, 
                                         text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"), 
                                         anchor="w")
        self.btn_limpeza.grid(row=1, column=0, padx=20, pady=10, sticky="ew")

        # --- Frame Principal ---
        self.limpeza_frame = ctk.CTkFrame(self, fg_color="transparent", corner_radius=0)
        self.limpeza_frame.grid_columnconfigure((0, 1), weight=1)
        self.limpeza_frame.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)

        self.setup_limpeza_frame()
        self.update_memory_info()

    def _extract_dependencies(self):
        """Copia os scripts embutidos do exe para o diretorio AppData permanente."""
        os.makedirs(self.base_dir, exist_ok=True)
        files_to_extract = ["backend.ps1"]
        
        for file in files_to_extract:
            src = os.path.join(self.bundle_dir, file)
            dst = os.path.join(self.base_dir, file)
            if os.path.exists(src):
                try:
                    shutil.copy2(src, dst)
                except Exception as e:
                    print(f"Erro ao extrair {file}: {e}")

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

if __name__ == "__main__":
    app = App()
    app.mainloop()
