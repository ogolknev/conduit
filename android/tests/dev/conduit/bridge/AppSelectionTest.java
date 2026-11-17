package dev.conduit.bridge;

import java.util.*;

public final class AppSelectionTest {
    private static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        List<AppSelection.App> apps = Arrays.asList(new AppSelection.App("org.first", "Музыка"),
                new AppSelection.App("org.second", "Музыка"), new AppSelection.App("com.cafe.app", "Café"),
                new AppSelection.App("org.notes", "Заметки и расчёт"));
        Set<String> saved = new HashSet<>(Arrays.asList("org.second", "org.unlisted"));
        AppSelection selection = new AppSelection(apps, saved);
        check(selection.search("  МУЗЫКА  ").size() == 2);
        check(selection.search("CAFE").get(0).packageName.equals("com.cafe.app"));
        check(selection.search("org.first музыка").size() == 1);
        check(selection.search("расчет").size() == 1);
        check(selection.search("missing").isEmpty());
        selection.setEnabled(selection.search("org.first").get(0).packageName, false);
        selection.setEnabled(selection.search("org.second").get(0).packageName, true);
        check(selection.search("").size() == 4);
        check(selection.blocked.contains("org.first") && !selection.blocked.contains("org.second"));
        check(selection.blocked.contains("org.unlisted"));
        check(!saved.contains("org.first") && saved.contains("org.second")); // Cancel leaves preferences intact.
        AppSelection reopened = new AppSelection(apps, selection.blocked);
        check(reopened.blocked.equals(selection.blocked));
        System.out.println("App selection: Unicode/name/package search, duplicate labels, edits across queries and cancellation passed");
    }
}
