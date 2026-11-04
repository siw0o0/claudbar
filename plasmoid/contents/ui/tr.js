.pragma library

// Translations without a gettext build step: English is the source, others by locale prefix.
var catalogs = {
    pl: {
        "No active session": "Brak aktywnej sesji",
        "no session": "bez sesji",
        "waiting for approval": "czeka na zgodę",
        "waiting for you": "czeka na ciebie",
        "Width": "Szerokość",
        "Width of the bar on the panel": "Szerokość paska na panelu",
        "working": "pracuje",
        "done": "gotowe",
        "now": "teraz",
        "%1 ago": "%1 temu",
        "Context": "Kontekst",
        "5 h": "5 h",
        "Week": "Tydzień",
        "Sessions · %1": "Sesje · %1",
        "click to open the chat": "kliknij, by otworzyć czat",
        "Pin to the panel": "Przypnij na pasku",
        "Unpin from the panel": "Odepnij z paska",
        "Rename": "Zmień nazwę",
        "Limits read %1": "Odczyt limitów %1",
        "total %1": "razem %1",
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
