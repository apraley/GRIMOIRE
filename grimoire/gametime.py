"""Game calendar. One tick is one day; months are 30 days, years 360 days."""
from __future__ import annotations

from .serial import serializable

MONTHS = ["Ianus", "Ferren", "Marth", "Aprel", "Maia", "Junos",
          "Quintil", "Sextil", "Septen", "Octen", "Noven", "Decen"]
MONTH_ABBR = [m[:3] for m in MONTHS]
DAYS_PER_MONTH = 30
MONTHS_PER_YEAR = 12
DAYS_PER_YEAR = DAYS_PER_MONTH * MONTHS_PER_YEAR
WEEKDAYS = ["Moonday", "Ashday", "Wensday", "Thornsday", "Freeday", "Sabbath", "Sunsday"]

SEASONS = ["Winter", "Spring", "Summer", "Autumn"]


@serializable
class Clock:
    def __init__(self, start_year: int = 2049, start_day: int = 0):
        self.day = 0            # absolute days since campaign start
        self.start_year = start_year
        self.start_day = start_day

    # -- derived ----------------------------------------------------------
    @property
    def abs_day(self) -> int:
        return self.start_day + self.day

    @property
    def year(self) -> int:
        return self.start_year + self.abs_day // DAYS_PER_YEAR

    @property
    def doy(self) -> int:
        return self.abs_day % DAYS_PER_YEAR

    @property
    def month(self) -> int:
        return self.doy // DAYS_PER_MONTH

    @property
    def dom(self) -> int:
        return self.doy % DAYS_PER_MONTH + 1

    @property
    def weekday(self) -> str:
        return WEEKDAYS[self.abs_day % 7]

    @property
    def quarter(self) -> int:
        return self.month // 3 + 1

    def season(self, latitude: float = 45.0) -> str:
        """Northern-hemisphere seasons flip below the equator."""
        idx = ((self.month + 1) % 12) // 3
        if latitude < 0:
            idx = (idx + 2) % 4
        return SEASONS[idx]

    def is_month_end(self) -> bool:
        return self.dom == DAYS_PER_MONTH

    def is_quarter_end(self) -> bool:
        return self.is_month_end() and (self.month + 1) % 3 == 0

    def is_year_end(self) -> bool:
        return self.month == 11 and self.dom == DAYS_PER_MONTH

    def is_week_end(self) -> bool:
        return self.abs_day % 7 == 6

    def advance(self, days: int = 1) -> None:
        self.day += days

    # -- formatting -------------------------------------------------------
    def short(self) -> str:
        return f"{self.dom:02d} {MONTH_ABBR[self.month]} {self.year}"

    def long(self) -> str:
        return f"{self.weekday}, {self.dom} {MONTHS[self.month]} {self.year}"

    def stamp(self) -> str:
        return f"{self.year}-{self.month + 1:02d}-{self.dom:02d}"

    def __str__(self) -> str:
        return self.short()


def days_between(a: int, b: int) -> int:
    return abs(a - b)


def years_of(days: int) -> float:
    return days / DAYS_PER_YEAR


def fmt_duration(days: int) -> str:
    if days < 1:
        return "today"
    if days < 30:
        return f"{days}d"
    if days < DAYS_PER_YEAR:
        return f"{days // 30}mo"
    y, rem = divmod(days, DAYS_PER_YEAR)
    return f"{y}y" + (f" {rem // 30}mo" if rem >= 30 else "")
