# astrbot_gmod_monitor.py (伪代码框架)

import os
import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class CrashLogHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if "crash_log.txt" in event.src_path:
            # 检测到崩溃日志更新
            self.analyze_crash()
    
    def analyze_crash(self):
        # 1. 读取最近的 E2 代码
        e2_log_path = "D:/gmod/Gmod/gmod/garrysmod/data/e2_logs/e2_uploads.txt"
        
        with open(e2_log_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 2. 提取最后一条 E2 记录
        entries = content.split("========================================")
        last_entry = entries[-2] if len(entries) >= 2 else None
        
        if last_entry:
            # 3. 发送给 LLM 分析
            prompt = f"""
            GMod 服务器刚刚崩溃。以下是崩溃前最后上传的 E2 代码。
            请分析这段代码是否包含恶意逻辑（如死循环、无限生成实体等）。
            
            {last_entry}
            
            请回答：
            1. 是否恶意？(是/否/不确定)
            2. 原因分析
            3. 建议处理方式
            """
            
            # 调用 LLM API
            response = call_llm(prompt)
            
            # 4. 发送到 QQ 群
            send_to_qq_group(f"[GMod监控] 服务器崩溃分析：\n{response}")
