"""Interactive command-line interface for the card counting app."""

from __future__ import annotations

import argparse
import cmd
import sys
from textwrap import dedent
from typing import Sequence

from .engine import CardCounter, CardParsingError, parse_card_strings


class CardCounterShell(cmd.Cmd):
    intro = dedent(
        """
        Card Counting App (Hi-Lo)
        Type 'help' for a list of commands or 'exit' to quit.
        """
    ).strip()
    prompt = "(count) "

    def __init__(self, counter: CardCounter, bet_unit: float) -> None:
        super().__init__()
        self._counter = counter
        self._bet_unit = bet_unit

    # ----- core commands -------------------------------------------------

    def do_deal(self, arg: str) -> None:
        """deal <cards> - Record one or more dealt cards (e.g. 'deal AS 10H 7C')."""

        try:
            cards = parse_card_strings(arg)
            self._counter.deal(cards)
            self._print_status()
        except (ValueError, CardParsingError) as exc:
            self._print_error(exc)

    def do_status(self, _: str) -> None:
        """Show current running count, true count and cards remaining."""

        self._print_status()

    def do_remaining(self, _: str) -> None:
        """List remaining cards in the shoe by rank."""

        remaining = self._counter.remaining_by_rank
        total_cards = self._counter.cards_remaining
        print(f"Cards remaining: {total_cards}")
        for rank in sorted(remaining):
            print(f"  {rank:>2}: {remaining[rank]}")

    def do_reset(self, arg: str) -> None:
        """reset [decks] - Reset the shoe with optional new deck count."""

        arg = arg.strip()
        decks = None
        if arg:
            try:
                decks = int(arg)
            except ValueError:
                self._print_error("Decks must be an integer")
                return

        try:
            self._counter.reset(decks)
            print("Shoe reset.")
            self._print_status()
        except ValueError as exc:
            self._print_error(exc)

    def do_undo(self, arg: str) -> None:
        """undo [count] - Undo the last dealt card(s)."""

        arg = arg.strip()
        count = 1
        if arg:
            try:
                count = int(arg)
            except ValueError:
                self._print_error("Undo count must be an integer")
                return

        try:
            self._counter.undo(count)
            self._print_status()
        except ValueError as exc:
            self._print_error(exc)

    def do_bet(self, _: str) -> None:
        """Show recommended betting units based on the current true count."""

        bet = self._counter.suggest_bet_spread(self._bet_unit)
        true_count = self._counter.true_count
        if true_count is None:
            print("No cards remaining. Shuffle and reset the shoe.")
        else:
            print(
                f"True count: {true_count:.2f}\n"
                f"Suggested bet spread: {bet:.2f} units"
            )

    def do_history(self, arg: str) -> None:
        """history [limit] - Show recently logged cards."""

        arg = arg.strip()
        history = self._counter.history
        if not history:
            print("No cards have been recorded yet.")
            return

        limit = len(history)
        if arg:
            try:
                limit = max(0, int(arg))
            except ValueError:
                self._print_error("Limit must be an integer")
                return

        recent = history[-limit:] if limit else history
        print("Recent cards:")
        print(" ".join(recent))

    def do_exit(self, _: str) -> bool:  # type: ignore[override]
        """Exit the application."""

        print("Good luck at the tables!")
        return True

    do_quit = do_exit
    do_EOF = do_exit

    # ----- helpers -------------------------------------------------------

    def _print_status(self) -> None:
        stats = self._counter.stats()
        true_count = stats["true_count"]
        true_count_display = "N/A" if true_count is None else f"{true_count:.2f}"
        print(
            "Running count: {running} | True count: {true} | Cards remaining: {remaining}"
            .format(
                running=stats["running_count"],
                true=true_count_display,
                remaining=stats["cards_remaining"],
            )
        )

    def _print_error(self, message: object) -> None:
        print(f"Error: {message}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the interactive card counting app.")
    parser.add_argument(
        "--decks",
        type=int,
        default=6,
        help="Number of decks in the shoe (default: 6)",
    )
    parser.add_argument(
        "--unit",
        type=float,
        default=1.0,
        help="Base betting unit to use for suggestions (default: 1)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        counter = CardCounter(decks=args.decks)
    except ValueError as exc:
        parser.error(str(exc))
        return 2

    if args.unit <= 0:
        parser.error("Base unit must be positive")
        return 2

    shell = CardCounterShell(counter, bet_unit=args.unit)
    shell.cmdloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
