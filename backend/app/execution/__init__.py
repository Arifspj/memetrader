"""Execution backends."""

from app.execution.base import ExecutionError, Executor, NeedsClientSignature
from app.execution.paper import PaperExecutor

__all__ = ["ExecutionError", "Executor", "NeedsClientSignature", "PaperExecutor", "build_executor"]


def build_executor(settings, jupiter=None) -> Executor:
    if settings.execution_mode == "jupiter":
        from app.clients.jupiter import JupiterClient
        from app.execution.jupiter_executor import JupiterExecutor

        return JupiterExecutor(jupiter or JupiterClient())
    return PaperExecutor()
