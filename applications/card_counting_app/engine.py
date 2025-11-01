"""Core card counting logic for the card counting app."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, List, Mapping, Sequence


class CardParsingError(ValueError):
    """Raised when a card string cannot be parsed."""


@dataclass(frozen=True)
class Card:
    """Simple representation of a playing card by rank and optional suit."""

    rank: str
    suit: str | None = None

    def __post_init__(self) -> None:
        object.__setattr__(self, "rank", self.rank.upper())
        if self.suit is not None:
            object.__setattr__(self, "suit", self.suit.upper())

    def __str__(self) -> str:  # pragma: no cover - delegated to __repr__
        return f"{self.rank}{self.suit or ''}"


_HI_LO_VALUES: Mapping[str, int] = {
    "2": 1,
    "3": 1,
    "4": 1,
    "5": 1,
    "6": 1,
    "7": 0,
    "8": 0,
    "9": 0,
    "10": -1,
    "J": -1,
    "Q": -1,
    "K": -1,
    "A": -1,
}

_BASE_RANK_COUNTS: Mapping[str, int] = {rank: 4 for rank in _HI_LO_VALUES}

_SUITS = {"S", "H", "D", "C"}


def parse_card_strings(raw: str) -> List[Card]:
    """Parse a whitespace separated list of card strings into :class:`Card` objects."""

    tokens = [token for token in raw.replace(",", " ").split() if token]
    return [parse_card(token) for token in tokens]


def parse_card(token: str) -> Card:
    """Parse a single card string."""

    cleaned = token.strip().upper()
    if not cleaned:
        raise CardParsingError("Empty card token")

    rank, suit = _extract_rank_and_suit(cleaned)
    _validate_rank(rank)
    suit = _normalize_suit(suit)
    return Card(rank=rank, suit=suit)


def _extract_rank_and_suit(token: str) -> tuple[str, str | None]:
    if token in {"T", "10"}:
        return "10", None

    if token[0] == "T":
        # Accept shorthand like "TD"
        return "10", token[1:] or None

    if token.startswith("10"):
        return "10", token[2:] or None

    rank = token[0]
    suit = token[1:] or None

    if rank == "1" and token.startswith("1"):
        # Guard against malformed sequences like "1H"
        raise CardParsingError(f"Ambiguous rank in token '{token}'")

    return rank, suit


def _validate_rank(rank: str) -> None:
    if rank not in _HI_LO_VALUES:
        raise CardParsingError(f"Unsupported card rank '{rank}'")


def _normalize_suit(suit: str | None) -> str | None:
    if suit is None:
        return None
    suit_char = suit[0]
    if suit_char not in _SUITS:
        raise CardParsingError(f"Unsupported suit '{suit}'")
    return suit_char


class CardCounter:
    """Tracks running and true counts for a blackjack shoe using Hi-Lo system."""

    def __init__(self, decks: int = 6) -> None:
        if decks <= 0:
            raise ValueError("Deck count must be a positive integer")
        self._initial_decks = decks
        self._running_count = 0
        self._history: List[str] = []
        self._remaining_counts: Dict[str, int] = {}
        self.reset()

    @property
    def initial_decks(self) -> int:
        return self._initial_decks

    @property
    def running_count(self) -> int:
        return self._running_count

    @property
    def cards_remaining(self) -> int:
        return sum(self._remaining_counts.values())

    @property
    def decks_remaining(self) -> float:
        return self.cards_remaining / 52 if self.cards_remaining else 0.0

    @property
    def true_count(self) -> float | None:
        decks_remaining = self.decks_remaining
        if decks_remaining == 0:
            return None
        return self._running_count / decks_remaining

    @property
    def history(self) -> Sequence[str]:
        return tuple(self._history)

    @property
    def remaining_by_rank(self) -> Mapping[str, int]:
        return dict(self._remaining_counts)

    def reset(self, decks: int | None = None) -> None:
        if decks is not None:
            if decks <= 0:
                raise ValueError("Deck count must be a positive integer")
            self._initial_decks = decks
        self._running_count = 0
        self._history.clear()
        self._remaining_counts = {
            rank: count * self._initial_decks for rank, count in _BASE_RANK_COUNTS.items()
        }

    def deal(self, cards: Iterable[Card | str]) -> None:
        parsed_cards = [parse_card(card) if isinstance(card, str) else card for card in cards]
        if not parsed_cards:
            raise ValueError("No cards supplied to deal")

        for card in parsed_cards:
            rank = card.rank
            if self._remaining_counts.get(rank, 0) <= 0:
                raise ValueError(f"No remaining '{rank}' cards in the shoe")
            self._remaining_counts[rank] -= 1
            self._running_count += _HI_LO_VALUES[rank]
            self._history.append(rank)

    def undo(self, count: int = 1) -> None:
        if count <= 0:
            raise ValueError("Undo count must be a positive integer")
        if count > len(self._history):
            raise ValueError("Cannot undo more cards than have been dealt")

        for _ in range(count):
            rank = self._history.pop()
            self._running_count -= _HI_LO_VALUES[rank]
            self._remaining_counts[rank] += 1

    def suggest_bet_spread(self, base_unit: float = 1.0) -> float:
        true_count = self.true_count
        if true_count is None:
            return base_unit
        if true_count < 1:
            return base_unit
        return base_unit * max(1.0, round(true_count))

    def stats(self) -> Dict[str, float | int | None]:
        return {
            "decks": self._initial_decks,
            "running_count": self._running_count,
            "true_count": None if self.true_count is None else round(self.true_count, 2),
            "cards_remaining": self.cards_remaining,
            "decks_remaining": round(self.decks_remaining, 2),
        }


__all__ = [
    "Card",
    "CardCounter",
    "CardParsingError",
    "parse_card",
    "parse_card_strings",
]
