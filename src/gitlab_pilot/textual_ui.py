from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, ListView, ListItem, Label
from textual.containers import Vertical
import sys

class ShowOptions(App):
    """Textual-based interactive selection menu without clearing previous logs."""

    def __init__(self, selection_list, txt) -> None:
        super().__init__()
        self.selection_list = selection_list + ["🔙 BACK", "❌ EXIT"]
        self.txt = txt

    def compose(self) -> ComposeResult:
        """Creates the UI layout with a header, footer, and selection list."""
        yield Header(name="GitLab Pilot", show_clock=True)
        yield Vertical(
            Label(f"🔍 Select a {self.txt} from the list below:"),
            ListView(
                *[ListItem(Label(f"[cyan]{item}[/cyan]")) for item in self.selection_list],  # ✅ Rich-colored labels
                id="options_list"
            )
        )
        yield Footer()

    def on_list_view_selected(self, event) -> None:
        """Handles user selection."""
        selected_option = event.item.children[0].plain
        if selected_option == "❌ EXIT":
            sys.exit(0)
        elif selected_option == "🔙 BACK":
            self.exit("menu")
        else:
            self.exit(selected_option)

# ✅ Move this function OUTSIDE the class
def show_options(selection_list, txt):
    """Runs the Textual selection app below previous Rich output without clearing the screen."""
    
    print("\n" * 2)  # Adds spacing so Textual UI starts below logs
    print(f"🔹 Please select a {txt} from the options below:")
    print("=" * 50)  # Keeps separation between Rich output and Textual UI

    app = ShowOptions(selection_list, txt)
    return app.run(log="textual.log", screen=False)  # ✅ Prevents screen clearing
