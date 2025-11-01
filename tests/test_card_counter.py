import math

import pytest

from applications.card_counting_app.engine import (
    CardCounter,
    CardParsingError,
    parse_card,
    parse_card_strings,
)


def test_parse_card_accepts_suits_and_aliases():
    assert parse_card("as").rank == "A"
    assert parse_card("td").rank == "10"
    assert parse_card("10H").rank == "10"

    with pytest.raises(CardParsingError):
        parse_card("1H")


def test_parse_card_strings_handles_commas_and_spaces():
    cards = parse_card_strings("AS, 10H 7c")
    assert [card.rank for card in cards] == ["A", "10", "7"]


def test_card_counter_deal_and_counts():
    counter = CardCounter(decks=1)
    counter.deal(["2", "3", "10", "AS"])

    assert counter.running_count == 0  # 2:+1, 3:+1, 10:-1, A:-1
    assert counter.cards_remaining == 48
    assert counter.remaining_by_rank["2"] == 3


def test_true_count_calculation():
    counter = CardCounter(decks=2)
    counter.deal(["2", "3", "4", "5", "6"])  # running = +5

    true_count = counter.true_count
    assert true_count is not None
    decks_remaining = counter.decks_remaining
    assert math.isclose(true_count, counter.running_count / decks_remaining)


def test_undo_reverses_counts():
    counter = CardCounter(decks=1)
    counter.deal(["10", "A", "5"])
    assert counter.running_count == -1

    counter.undo()
    assert counter.running_count == -2
    assert counter.cards_remaining == 50

    counter.undo(2)
    assert counter.running_count == 0
    assert counter.cards_remaining == 52


def test_deal_rejects_excess_cards():
    counter = CardCounter(decks=1)
    with pytest.raises(ValueError):
        for _ in range(5):
            counter.deal(["A", "A", "A", "A", "A"])


def test_reset_accepts_new_deck_count():
    counter = CardCounter(decks=1)
    counter.deal(["2", "3"])
    counter.reset(2)

    assert counter.initial_decks == 2
    assert counter.cards_remaining == 104
    assert counter.running_count == 0
