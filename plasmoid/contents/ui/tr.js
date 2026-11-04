.pragma library

// Translations without a gettext build step: English is the source, others by locale prefix.
var catalogs = {
    pl: {
        "No active session": "Brak aktywnej sesji",
        "no session": "bez sesji",
        "waiting for approval": "czeka na zgodę",
        "waiting for you": "czeka na ciebie",
        "Width": "Szerokość",
        "General": "Ogólne",
        "Width of the bar on the panel, in grid units. It never goes below what the meters need.": "Szerokość paska na panelu w jednostkach siatki. Nigdy nie spada poniżej tego, czego potrzebują liczniki.",
        "Percentages only, without the bars": "Same procenty, bez pasków",
        "working": "pracuje",
        "done": "gotowe",
        "now": "teraz",
        "%1 ago": "%1 temu",
        "Context": "Kontekst",
        "5 h": "5 h",
        "Week": "Tydzień",
        "Pin to the panel": "Przypnij na pasku",
        "Unpin from the panel": "Odepnij z paska",
        "Rename": "Zmień nazwę",
        "Compact": "Kompaktowy"
    }
};

var catalog = catalogs[Qt.locale().name.split("_")[0]] || {};

function tr(text) {
    var out = catalog[text] || text;
    for (var i = 1; i < arguments.length; i++)
        out = out.replace("%" + i, arguments[i]);
    return out;
}
