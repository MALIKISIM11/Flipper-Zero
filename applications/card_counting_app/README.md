# Card Counting App

An interactive command-line tool to help practice Hi-Lo card counting for blackjack games. It keeps track of running and true counts for multi-deck shoes, supports undoing mistakes, and offers a simple betting spread suggestion based on the current true count.

## Features

- Hi-Lo counting system with configurable shoe size.
- Running and true count tracking with automatic deck estimation.
- Undo support to correct input mistakes.
- Quick view of remaining cards by rank.
- Simple bet spread recommendation based on the true count.

## Usage

Run the interactive shell with Python:

```bash
python -m applications.card_counting_app.cli --decks 6 --unit 5
```

Within the shell:

- `deal <cards>` - log one or more cards, e.g. `deal AS 10H 7C`.
- `status` - show the running count, true count, and cards remaining.
- `remaining` - list remaining cards per rank.
- `undo [count]` - undo the last card(s).
- `reset [decks]` - reset the shoe, optionally adjusting the deck count.
- `bet` - display the suggested bet spread for the configured unit.
- `history [limit]` - show the most recent cards recorded.
- `exit` - quit the application.

Input is case-insensitive; suits are optional (`AH`, `as`, `a`, `10H`, `td`).

## Testing

The project includes a small pytest suite:

```bash
pytest tests/test_card_counter.py
```

## Notes

This tool is for educational purposes. Advantage play may be restricted or prohibited by casino rules and local regulations. Always follow the law and venue policies.
