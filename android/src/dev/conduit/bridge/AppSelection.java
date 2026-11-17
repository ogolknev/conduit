package dev.conduit.bridge;

import java.text.Normalizer;
import java.util.*;

/** Search and edits are independent of visible row positions. */
final class AppSelection {
    static final class App {
        final String packageName, label, search;
        App(String packageName, String label) {
            this.packageName = packageName; this.label = label;
            search = normalize(label + " " + packageName);
        }
    }
    final List<App> apps;
    final Set<String> blocked;
    AppSelection(List<App> apps, Set<String> blocked) {
        this.apps = new ArrayList<>(apps); this.blocked = new HashSet<>(blocked);
    }
    List<App> search(String query) {
        String normalized = normalize(query).trim();
        if (normalized.isEmpty()) return new ArrayList<>(apps);
        String[] terms = normalized.split("\\s+");
        List<App> result = new ArrayList<>();
        for (App app : apps) {
            boolean matches = true;
            for (String term : terms) if (!app.search.contains(term)) { matches = false; break; }
            if (matches) result.add(app);
        }
        return result;
    }
    void setEnabled(String packageName, boolean enabled) {
        if (enabled) blocked.remove(packageName); else blocked.add(packageName);
    }
    private static String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKD).replaceAll("\\p{M}+", "").toLowerCase(Locale.ROOT);
    }
}
