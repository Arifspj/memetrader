"""Snapshot of the user's exit configuration, decoupled from the ORM row."""

from __future__ import annotations

from dataclasses import dataclass

from app.engine.risk import RiskLimits, trailing_stop_for


@dataclass(slots=True)
class ExitParams:
    take_profit_pct: float
    stop_loss_pct: float
    trailing_activation_pct: float
    trailing_drop_pct: float
    max_hold_minutes: int

    def stop_for(self, entry_price: float) -> float:
        return round(entry_price * (1 - self.stop_loss_pct / 100.0), 12)

    def target_for(self, entry_price: float) -> float:
        return round(entry_price * (1 + self.take_profit_pct / 100.0), 12)

    def trailing_for(self, entry_price: float, peak_price: float) -> float | None:
        return trailing_stop_for(
            entry_price, peak_price, self.trailing_activation_pct, self.trailing_drop_pct
        )


def limits_from_settings(row) -> RiskLimits:
    return RiskLimits(
        risk_per_trade_pct=row.risk_per_trade_pct,
        max_open_positions=row.max_open_positions,
        max_daily_loss_pct=row.max_daily_loss_pct,
        min_entry_score=row.min_entry_score,
        max_price_impact_bps=row.max_price_impact_bps,
        starting_capital_usd=row.starting_capital_usd,
    )


def exit_params_from_settings(row) -> ExitParams:
    return ExitParams(
        take_profit_pct=row.take_profit_pct,
        stop_loss_pct=row.stop_loss_pct,
        trailing_activation_pct=row.trailing_activation_pct,
        trailing_drop_pct=row.trailing_drop_pct,
        max_hold_minutes=row.max_hold_minutes,
    )
