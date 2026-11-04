// KWin script: bring the Claude desktop app's main window back from minimized and focus it.
// Loaded and run by the widget over D-Bus (org.kde.KWin /Scripting) when a chat is opened.
const app = "com.anthropic.Claude";
for (const w of workspace.windowList()) {
    if (w.normalWindow && (w.desktopFileName === app || w.resourceClass === app)) {
        w.minimized = false;
        workspace.activeWindow = w;
        break;
    }
}
