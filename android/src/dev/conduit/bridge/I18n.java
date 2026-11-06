package dev.conduit.bridge;

import android.app.LocaleManager;
import android.content.Context;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.os.Build;
import android.os.LocaleList;
import java.util.Locale;

final class I18n {
    private static volatile Context localized;
    private I18n() { }
    static String selection(Context context) {
        if (Build.VERSION.SDK_INT >= 33) {
            LocaleManager manager=context.getSystemService(LocaleManager.class);
            if (manager!=null) {
                LocaleList locales=manager.getApplicationLocales();
                return locales.isEmpty()?"system":locales.get(0).getLanguage();
            }
        }
        return context.getSharedPreferences("settings",Context.MODE_PRIVATE).getString("language","system");
    }
    private static Locale locale(Context context) {
        String tag=selection(context);
        if ("en".equals(tag) || "ru".equals(tag)) return Locale.forLanguageTag(tag);
        LocaleList system=Build.VERSION.SDK_INT>=33?context.getSystemService(LocaleManager.class).getSystemLocales():Resources.getSystem().getConfiguration().getLocales();
        return !system.isEmpty() && "ru".equals(system.get(0).getLanguage())?Locale.forLanguageTag("ru"):Locale.ENGLISH;
    }
    static Context wrap(Context context) {
        Configuration configuration=new Configuration(context.getResources().getConfiguration());
        Locale locale=locale(context);configuration.setLocales(new LocaleList(locale));configuration.setLayoutDirection(locale);
        return context.createConfigurationContext(configuration);
    }
    static void refresh(Context context) { localized=wrap(context); }
    static String t(String key) {
        if (key==null) return "";
        Context context=localized;Integer id=LocalizedStrings.IDS.get(key);
        return context!=null && id!=null?context.getString(id):key;
    }
    static void select(Context context,String tag) {
        if (!"en".equals(tag) && !"ru".equals(tag)) tag="system";
        context.getSharedPreferences("settings",Context.MODE_PRIVATE).edit().putString("language",tag).apply();
        if (Build.VERSION.SDK_INT>=33) {
            LocaleManager manager=context.getSystemService(LocaleManager.class);
            if (manager!=null) manager.setApplicationLocales("system".equals(tag)?LocaleList.getEmptyLocaleList():LocaleList.forLanguageTags(tag));
        }
        refresh(context);
    }
}
