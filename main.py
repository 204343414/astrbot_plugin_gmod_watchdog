import os
import time
import asyncio
import logging
from astrbot.api.all import *
from astrbot.api.message_components import Plain

@register("gmod_monitor", "YourName", "GMod服务器监控插件", "1.0.0")
class GmodMonitorPlugin(Star):
    def __init__(self, context: Context, config: dict, *args, **kwargs):
        super().__init__(context)
        self.logger = logging.getLogger("gmod_monitor")
        self.config = config
        
        # ============ 配置区域 ============
        # 修改成你的实际路径
        self.e2_log_path = r"D:\gmod\Gmod\gmod\garrysmod\data\e2_logs\e2_uploads.txt"
        self.crash_log_path = r"D:\gmod\Gmod\gmod\garrysmod\data\crash_log.txt"
        
        # 记录上次读取位置
        self.last_e2_size = 0
        self.last_crash_size = 0
        
        # 初始化时记录当前文件大小（避免启动时读取全部历史）
        if os.path.exists(self.e2_log_path):
            self.last_e2_size = os.path.getsize(self.e2_log_path)
        if os.path.exists(self.crash_log_path):
            self.last_crash_size = os.path.getsize(self.crash_log_path)
        
        # 启动后台监控
        asyncio.create_task(self._monitor_loop())
        self.logger.info("GMod 监控插件已启动")

    async def _monitor_loop(self):
        """后台循环监控日志文件"""
        while True:
            try:
                await self._check_crash_log()
            except Exception as e:
                self.logger.error(f"监控出错: {e}")
            await asyncio.sleep(10)  # 每10秒检查一次

    async def _check_crash_log(self):
        """检查是否有新的崩溃记录"""
        if not os.path.exists(self.crash_log_path):
            return
        
        current_size = os.path.getsize(self.crash_log_path)
        if current_size > self.last_crash_size:
            # 有新内容，说明服务器刚崩溃重启
            self.logger.info("检测到服务器崩溃！")
            
            # 读取最近的 E2 代码
            last_e2 = self._get_last_e2_entry()
            
            if last_e2:
                # 这里可以调用 LLM 分析
                # 暂时只是记录，具体 LLM 调用需要根据你的 AstrBot 配置
                self.logger.info(f"崩溃前最后的 E2 上传:\n{last_e2}")
            
            self.last_crash_size = current_size

    def _get_last_e2_entry(self):
        """获取最后一条 E2 上传记录"""
        if not os.path.exists(self.e2_log_path):
            return None
        
        try:
            with open(self.e2_log_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # 按分隔符切割
            entries = content.split("========================================")
            # 过滤空白
            entries = [e.strip() for e in entries if e.strip()]
            
            if entries:
                return entries[-1]  # 返回最后一条
            return None
        except Exception as e:
            self.logger.error(f"读取 E2 日志失败: {e}")
            return None

    def _get_recent_e2_entries(self, count=5):
        """获取最近的几条 E2 记录"""
        if not os.path.exists(self.e2_log_path):
            return []
        
        try:
            with open(self.e2_log_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            entries = content.split("========================================")
            entries = [e.strip() for e in entries if e.strip()]
            
            return entries[-count:] if len(entries) >= count else entries
        except Exception as e:
            self.logger.error(f"读取 E2 日志失败: {e}")
            return []

    @command("gmod状态")
    async def cmd_status(self, event: AstrMessageEvent):
        """查看 GMod 服务器状态"""
        lines = ["📊 GMod 服务器监控状态", ""]
        
        # 检查 E2 日志
        if os.path.exists(self.e2_log_path):
            size = os.path.getsize(self.e2_log_path)
            lines.append(f"✅ E2日志: {size/1024:.1f} KB")
        else:
            lines.append("❌ E2日志: 不存在")
        
        # 检查崩溃日志
        if os.path.exists(self.crash_log_path):
            size = os.path.getsize(self.crash_log_path)
            lines.append(f"⚠️ 崩溃日志: {size/1024:.1f} KB (有崩溃记录)")
        else:
            lines.append("✅ 崩溃日志: 无 (服务器未崩溃过)")
        
        yield event.plain_result("\n".join(lines))

    @command("最近e2")
    async def cmd_recent_e2(self, event: AstrMessageEvent, count: str = "3"):
        """查看最近的 E2 上传记录"""
        try:
            n = int(count)
            n = min(n, 10)  # 最多10条
        except:
            n = 3
        
        entries = self._get_recent_e2_entries(n)
        
        if not entries:
            yield event.plain_result("📭 暂无 E2 上传记录")
            return
        
        lines = [f"📋 最近 {len(entries)} 条 E2 上传记录:", ""]
        
        for i, entry in enumerate(entries, 1):
            # 提取关键信息（简化显示）
            entry_lines = entry.split('\n')
            summary = []
            for line in entry_lines[:6]:  # 只取前6行（元信息）
                if line.strip():
                    summary.append(line.strip())
            lines.append(f"【{i}】" + " | ".join(summary[:3]))
        
        yield event.plain_result("\n".join(lines))

    @command("分析e2")
    async def cmd_analyze_e2(self, event: AstrMessageEvent):
        """让 LLM 分析最后一条 E2 代码是否恶意"""
        last_e2 = self._get_last_e2_entry()
        
        if not last_e2:
            yield event.plain_result("📭 暂无 E2 记录可分析")
            return
        
        yield event.plain_result("🔍 正在分析最后一条 E2 代码...")
        
        # 构造 LLM 分析提示
        prompt = f"""你是一个 GMod Wiremod Expression 2 代码审计专家。
请分析以下 E2 代码是否包含恶意逻辑（如死循环、无限生成实体、资源耗尽攻击等）。

{last_e2}

请回答：
1. 是否恶意？(是/否/不确定)
2. 风险等级：(高/中/低/无)
3. 原因分析（简短）
4. 建议处理方式"""
        
        # 调用 LLM
        # AstrBot 的 LLM 调用方式可能是这样（需要根据你的版本调整）
        try:
            func_tools_mgr = self.context.get_llm_tools_manager()
            llm_response = await self.context.get_using_provider().text_chat(
                prompt=prompt,
                session_id=event.session_id
            )
            
            if llm_response and llm_response.completion_text:
                yield event.plain_result(f"🤖 E2 代码分析结果:\n\n{llm_response.completion_text}")
            else:
                yield event.plain_result("❌ LLM 分析失败，未返回结果")
        except Exception as e:
            self.logger.error(f"LLM 调用失败: {e}")
            yield event.plain_result(f"❌ LLM 调用出错: {e}\n\n原始记录:\n{last_e2[:500]}...")

    @command("清空e2日志")
    async def cmd_clear_e2(self, event: AstrMessageEvent):
        """清空 E2 日志文件"""
        if os.path.exists(self.e2_log_path):
            try:
                with open(self.e2_log_path, 'w', encoding='utf-8') as f:
                    f.write("")
                self.last_e2_size = 0
                yield event.plain_result("✅ E2 日志已清空")
            except Exception as e:
                yield event.plain_result(f"❌ 清空失败: {e}")
        else:
            yield event.plain_result("📭 E2 日志文件不存在")
