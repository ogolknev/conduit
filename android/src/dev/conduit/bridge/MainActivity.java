package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import rikka.shizuku.Shizuku;
import android.content.*;
import android.content.pm.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import java.util.*;

public final class MainActivity extends Activity {
    private TextView connection, access, pairing, clipboardState, heroTitle, stateBadge;
    private Button bluetoothButton, pairButton;
    private SettingsRow backgroundRow, notificationPermissionRow, applicationsRow, manualClipboardRow, connectionControlRow, authorizationRow;
    private TextView settingsConnectionState;
    private SettingsRow appearanceRow, languageRow;
    private MinimalSwitch autoClipboard;
    private LinearLayout page;
    private int selectedPage;
    private int canvas, surface, ink, muted, accent, soft, line, success, warning, error, info;
    private SettingsRow bluetoothPermissionRow, ownNotificationsRow, shizukuPermissionRow;
    private boolean discoverAfterPermission, bluetoothBusy;
    private int startAttempt;
    private Runnable startupTimeout;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Shizuku.OnRequestPermissionResultListener permissionResult = (code, grant) -> {
        if (code == 57) { if(grant==PackageManager.PERMISSION_GRANTED && BridgeService.instance!=null && BridgeService.instance.clipboard!=null) BridgeService.instance.clipboard.startIfWanted(); refreshState(); return; }
        if (code != 55) return;
        getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("autoClipboard", grant == PackageManager.PERMISSION_GRANTED).apply();
        if (grant == PackageManager.PERMISSION_GRANTED && BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.startIfWanted();
        if (autoClipboard != null) autoClipboard.setChecked(grant == PackageManager.PERMISSION_GRANTED);
        refreshState();
    };
    private final Runnable update = new Runnable() {
        @Override public void run() { refreshState(); handler.postDelayed(this, 2000); }
    };

    @Override protected void attachBaseContext(Context base) {
        base=I18n.wrap(base);
        String appearance=base.getSharedPreferences("settings",MODE_PRIVATE).getString("appearance","system");
        if (!"system".equals(appearance)) {
            Configuration configuration=new Configuration(base.getResources().getConfiguration());
            configuration.uiMode=(configuration.uiMode & ~Configuration.UI_MODE_NIGHT_MASK) | ("dark".equals(appearance) ? Configuration.UI_MODE_NIGHT_YES : Configuration.UI_MODE_NIGHT_NO);
            base=base.createConfigurationContext(configuration);
        }
        super.attachBaseContext(base);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) { discoverAfterPermission = state.getBoolean("discoverAfterPermission"); selectedPage = state.getInt("page", 0); }
        I18n.refresh(getApplicationContext());
        PhoneDiagnostics.record(this, "activity.open");
        boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        canvas = Color.parseColor(dark ? "#151515" : "#FFFFFF"); surface = Color.parseColor(dark ? "#1C1C1C" : "#FFFFFF");
        ink = Color.parseColor(dark ? "#F2F2F2" : "#191919"); muted = Color.parseColor(dark ? "#ABABAB" : "#696969");
        accent = Color.parseColor(dark ? "#EDEDED" : "#202020"); soft = Color.parseColor(dark ? "#292929" : "#F3F3F3");
        line = Color.parseColor(dark ? "#333333" : "#E8E8E8");
        success=Color.parseColor(dark?"#76D39A":"#23834C"); warning=Color.parseColor(dark?"#EAC17A":"#97640F");
        error=Color.parseColor(dark?"#F29696":"#C83B3B"); info=Color.parseColor(dark?"#A3C3FF":"#356DD4");
        getWindow().setStatusBarColor(Color.TRANSPARENT); getWindow().setNavigationBarColor(Color.TRANSPARENT);
        getWindow().getDecorView().setSystemUiVisibility((dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR) | (Build.VERSION.SDK_INT < 30 ? View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION : 0));
        if (Build.VERSION.SDK_INT >= 29) getWindow().setNavigationBarContrastEnforced(false);
        if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);
        buildScreen();
        Shizuku.addRequestPermissionResultListener(permissionResult);
        handleShare(getIntent());
    }

    private void buildScreen() {
        connection = access = clipboardState = heroTitle = stateBadge = null;
        bluetoothButton = pairButton = null; autoClipboard = null;
        backgroundRow = notificationPermissionRow = applicationsRow = manualClipboardRow = connectionControlRow = authorizationRow = null;
        settingsConnectionState = null; appearanceRow = languageRow = null;
        bluetoothPermissionRow = ownNotificationsRow = shizukuPermissionRow = null;
        LinearLayout shell = column(); shell.setBackgroundColor(canvas);
        shell.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setClipToPadding(false); scroll.setVerticalScrollBarEnabled(false);
        page = column(); page.setPadding(dp(24), dp(22), dp(24), dp(28)); scroll.addView(page);
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout brand = row();
        IconView mark = new IconView("mark", canvas); mark.setPadding(0, 0, 0, 0);
        brand.addView(mark, new LinearLayout.LayoutParams(dp(32), dp(32)));
        TextView wordmark = label("Conduit", 20, true, ink); LinearLayout.LayoutParams wordmarkParams = new LinearLayout.LayoutParams(0, -2, 1); wordmarkParams.leftMargin = dp(11); brand.addView(wordmark, wordmarkParams);

        if (selectedPage != 2) { page.addView(brand); gap(page, 32); }
        if (selectedPage == 0) overviewPage(); else if (selectedPage == 1) filesPage(); else settingsPage();
        View divider = new View(this); divider.setBackgroundColor(line); shell.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
        LinearLayout nav = row(); nav.setBaselineAligned(false); nav.setPadding(dp(12), dp(7), dp(12), dp(7)); nav.setBackgroundColor(surface);
        String[] titles = {t("Устройства"), t("Файлы"), t("Настройки")}, icons = {"home", "folder", "settings"};
        for (int i = 0; i < titles.length; i++) {
            final int index = i; LinearLayout item = column(); item.setGravity(Gravity.CENTER); item.setPadding(dp(8), dp(9), dp(8), dp(9));
            if (selectedPage == i) item.setBackground(shape(soft, 7, false));
            int color = selectedPage == i ? accent : muted;
            item.addView(new IconView(icons[i], ink), new LinearLayout.LayoutParams(dp(23), dp(23))); gap(item, 5);
            TextView caption=label(titles[i],11,false,color);
            caption.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
            caption.setSingleLine(true); caption.setEllipsize(android.text.TextUtils.TruncateAt.END);
            caption.setGravity(Gravity.CENTER); caption.setTextAlignment(View.TEXT_ALIGNMENT_CENTER); caption.setLineSpacing(0,1);
            android.graphics.Paint.FontMetricsInt metrics=caption.getPaint().getFontMetricsInt();
            int captionHeight=Math.max(dp(18),metrics.bottom-metrics.top);
            item.addView(caption,new LinearLayout.LayoutParams(-1,captionHeight));
            item.setContentDescription(titles[i]); item.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
            item.setSelected(selectedPage == i); item.setOnClickListener(v -> { selectedPage = index; buildScreen(); });
            nav.addView(item, new LinearLayout.LayoutParams(0, -2, 1));
        }
        shell.addView(nav); setContentView(shell); shell.requestApplyInsets(); refreshState();
    }

    private void overviewPage() {
        stateBadge = label("", 12, true, accent); stateBadge.setPadding(0, dp(2), 0, dp(2));
        page.addView(stateBadge, new LinearLayout.LayoutParams(-2, -2)); gap(page, 20);
        heroTitle = label(t("Устройства"), 28, true, ink); heroTitle.setLetterSpacing(-0.035f); page.addView(heroTitle); gap(page, 10);
        gap(page, 18);
        LinearLayout hero = card();
        LinearLayout device = row(); device.addView(iconTile("laptop", 44), new LinearLayout.LayoutParams(dp(44), dp(54)));
        LinearLayout deviceText = column(); LinearLayout.LayoutParams deviceParams = new LinearLayout.LayoutParams(0, -2, 1); deviceParams.leftMargin = dp(16);
        deviceText.addView(label("Mac", 20, true, ink)); gap(deviceText, 6);
        connection = label("", 13, false, muted); deviceText.addView(connection); device.addView(deviceText, deviceParams); hero.addView(device);
        gap(hero, 22);
        bluetoothButton = button(hero, t("Включить соединение"), () -> {
            if (BridgeService.client != null) new AlertDialog.Builder(this).setTitle(t("Отключиться от Mac?")).setMessage(t("Буфер, уведомления и передача файлов будут приостановлены.")).setNegativeButton(t("Отмена"), null).setPositiveButton(t("Отключить"), (d, w) -> disconnect()).show();
            else if (BridgeService.instance == null || !BridgeService.instance.isBluetoothListening()) beginBluetooth(false);
            else showConnectionHelp();
        }, true);
        pairButton = textButton(hero, t("Добавить Mac"), () -> beginBluetooth(true));
        page.addView(hero); gap(page, 20);
        LinearLayout features = card(); features.setPadding(dp(18), dp(4), dp(18), dp(4));
        feature(features, "clipboard", t("Буфер обмена"), t("Передача текста"), true);
        rule(features);
        feature(features, "bell", t("Уведомления"), t("Передача уведомлений на Mac"), false);
        page.addView(features); gap(page, 24);
        LinearLayout quick = row();
        LinearLayout caption = column(); caption.addView(label(t("Передача файлов"), 14, true, ink)); gap(caption, 5); caption.addView(label(t("Файлы между Mac и Android"), 12, false, muted));
        quick.addView(caption, new LinearLayout.LayoutParams(0, -2, 1));
        Button send = smallButton(t("Отправить"), () -> { selectedPage = 1; buildScreen(); }); quick.addView(send); page.addView(quick);
    }

    private void feature(LinearLayout parent, String icon, String title, String subtitle, boolean clipboard) {
        LinearLayout feature = row(); feature.setPadding(0, dp(17), 0, dp(17));
        feature.addView(iconTile(icon, 32), new LinearLayout.LayoutParams(dp(32), dp(32)));
        LinearLayout words = column(); LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -2, 1); params.leftMargin = dp(13);
        words.addView(label(title, 15, true, ink)); gap(words, 5);
        TextView detail = label(subtitle, 12, false, muted); words.addView(detail);
        if (clipboard) clipboardState = detail; else access = detail;
        feature.addView(words, params);
        IconView chevron = new IconView("chevron", muted); feature.addView(chevron, new LinearLayout.LayoutParams(dp(18), dp(18)));
        feature.setBackground(pressBackground(Color.TRANSPARENT, soft));
        feature.setOnClickListener(v -> { selectedPage = 2; buildScreen(); });
        feature.setContentDescription(title + t(", открыть настройки")); parent.addView(feature);
    }

    private void filesPage() {
        heading(t("Файлы"));
        LinearLayout drop = card(); drop.setGravity(Gravity.CENTER_HORIZONTAL); drop.setPadding(dp(24), dp(34), dp(24), dp(30));
        drop.addView(iconTile("upload", 48), new LinearLayout.LayoutParams(dp(48), dp(48))); gap(drop, 24);
        TextView title = label(t("Отправить файлы"), 20, true, ink); title.setGravity(Gravity.CENTER); drop.addView(title); gap(drop, 10);
        TextView hint = label(t("Фото, документы и другие файлы"), 14, false, muted); hint.setGravity(Gravity.CENTER); drop.addView(hint); gap(drop, 26);
        button(drop, t("Выбрать файлы"), this::chooseFiles, true); page.addView(drop); gap(page, 24);
        LinearLayout help = card();
        help.addView(label(t("Отправка из приложений"), 16, true, ink)); gap(help, 10);
        help.addView(label(t("Файл → Поделиться → Conduit. При отсутствии соединения файл сохраняется в очереди."), 14, false, muted));
        page.addView(help); gap(page, 20);
        page.addView(label(t("По Bluetooth — до 100 МБ на файл. Очередь — до 32 файлов, суммарно 1 ГБ."), 12, false, muted));
    }

    private void settingsPage() {
        heading(t("Настройки"));
        section(t("СОЕДИНЕНИЕ")); LinearLayout connect = settingsCard();
        settingsConnectionState = label("", 13, false, muted); settingsConnectionState.setPadding(0,dp(14),0,dp(14)); connect.addView(settingsConnectionState);
        rowDivider(connect);
        authorizationRow = new SettingsRow(connect, t("Добавить Mac"), "", () -> beginBluetooth(true), "chevron");
        new SettingsRow(connect, "Bluetooth", "", () -> startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS)), "chevron");
        bluetoothPermissionRow = new SettingsRow(connect,t("Доступ Bluetooth"),"",this::openApplicationSettings,"chevron");
        backgroundRow = new SettingsRow(connect, t("Работа в фоне"), "", this::requestBackground, "chevron");
        rowDivider(connect);
        connectionControlRow = new SettingsRow(connect, "", "", () -> {
            BridgeService current=BridgeService.instance;
            boolean needsRetry=current!=null && BridgeService.client==null && getSharedPreferences("settings",MODE_PRIVATE).getBoolean("bluetoothWanted",false) && !current.isBluetoothListening();
            if (current==null || needsRetry) beginBluetooth(false); else confirmDisconnect();
        }, "");
        page.addView(connect); gap(page, 24);

        section(t("БУФЕР ОБМЕНА")); LinearLayout clip = settingsCard();
        autoClipboard = switchRow(clip, t("Автоматическая отправка"), getSharedPreferences("settings", MODE_PRIVATE).getBoolean("autoClipboard", false));
        autoClipboard.setOnCheckedChangeListener((v, enabled) -> setAutoClipboard(enabled));
        clipboardState = label("", 12, false, muted); clip.addView(clipboardState); gap(clip,12);
        rowDivider(clip);
        manualClipboardRow = new SettingsRow(clip, t("Отправить буфер"), "", this::sendClipboard, "send");
        shizukuPermissionRow=new SettingsRow(clip,t("Доступ Shizuku"),"",this::configureShizuku,"chevron");
        new SettingsRow(clip, t("О Shizuku"), "", this::showShizukuHelp, "chevron");
        page.addView(clip); gap(page, 24);

        section(t("УВЕДОМЛЕНИЯ")); LinearLayout notifications = settingsCard();
        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        MinimalSwitch forwarding = switchRow(notifications, t("Передавать на Mac"), prefs.getBoolean("forward", true));
        forwarding.setOnCheckedChangeListener((v, enabled) -> { prefs.edit().putBoolean("forward", enabled).apply(); refreshState(); });
        rowDivider(notifications);
        notificationPermissionRow = new SettingsRow(notifications, t("Чтение уведомлений"), "", this::openNotificationAccessSettings, "chevron");
        ownNotificationsRow=new SettingsRow(notifications,t("Уведомления Conduit"),"",this::configureOwnNotifications,"chevron");
        applicationsRow = new SettingsRow(notifications, t("Приложения"), "", this::chooseApps, "chevron");
        page.addView(notifications); gap(page,24);

        section(t("ДИАГНОСТИКА")); LinearLayout diagnostics = settingsCard();
        new SettingsRow(diagnostics,t("Скопировать отчёт"),"",this::copyDiagnostics,"copy");
        new SettingsRow(diagnostics,t("Автоперенос журнала"),t("Настраивается на Mac"),() -> new AlertDialog.Builder(this).setTitle(t("Автоперенос журнала")).setMessage(t("На Mac: Conduit → Настройки → Диагностика. Журнал передаётся при подключении и раз в минуту. Текст буфера, уведомления и коды исключены из отчёта.")).setPositiveButton(t("Закрыть"),null).show(),"chevron");
        page.addView(diagnostics); gap(page,24);

        section(t("ИНТЕРФЕЙС")); LinearLayout appearance=settingsCard();
        appearanceRow=new SettingsRow(appearance,t("Оформление"),"",this::chooseAppearance,"chevron");
        languageRow=new SettingsRow(appearance,t("Язык"),"",this::chooseLanguage,"chevron");
        page.addView(appearance); gap(page,24);
        LinearLayout trust = settingsCard();
        new SettingsRow(trust,t("Забыть разрешённые Mac"),"",this::forgetMacs,""); page.addView(trust); gap(page,20);
        String version=""; try { version=getPackageManager().getPackageInfo(getPackageName(),0).versionName; } catch(PackageManager.NameNotFoundException ignored) {}
        page.addView(label("Conduit " + version,12,false,muted));
    }
    private void chooseLanguage() {
        String[] values={"system","en","ru"}, labels={t("Системный"),"English","Русский"};
        String current=I18n.selection(this); int selected="en".equals(current)?1:"ru".equals(current)?2:0;
        new AlertDialog.Builder(this).setTitle(t("Язык")).setSingleChoiceItems(labels,selected,(dialog,which)-> {
            dialog.dismiss(); I18n.select(this,values[which]);
            if (Build.VERSION.SDK_INT<33) recreate();
        }).setNegativeButton(t("Отмена"),null).show();
    }
    private void chooseAppearance() {
        String[] values={"system","light","dark"}, labels={t("Системное"),t("Светлое"),t("Тёмное")};
        String current=getSharedPreferences("settings",MODE_PRIVATE).getString("appearance","system");
        int selected="light".equals(current)?1:"dark".equals(current)?2:0;
        new AlertDialog.Builder(this).setTitle(t("Оформление")).setSingleChoiceItems(labels,selected,(dialog,which)-> {
            getSharedPreferences("settings",MODE_PRIVATE).edit().putString("appearance",values[which]).apply(); dialog.dismiss(); recreate();
        }).setNegativeButton(t("Отмена"),null).show();
    }
    private void showShizukuHelp() {
        new AlertDialog.Builder(this).setTitle(t("Автоматическая отправка")).setMessage(t("Для чтения буфера в фоне требуется запущенный Shizuku и разрешение Conduit. После перезагрузки Android Shizuku необходимо запустить повторно.\n\nПри полной блокировке Android чтение приостанавливается до разблокировки.")).setPositiveButton(t("Закрыть"),null).show();
    }
    private void confirmDisconnect() {
        new AlertDialog.Builder(this).setTitle(t("Отключить соединение?")).setMessage(t("Передача буфера, уведомлений и файлов будет приостановлена.")).setNegativeButton(t("Отмена"),null).setPositiveButton(t("Отключить"),(d,w)->disconnect()).show();
    }
    private void refreshState() {
        PhoneNotifications.ensureConnected(this);
        if(languageRow!=null) { String selected=I18n.selection(this); languageRow.setStatus("en".equals(selected)?"English":"ru".equals(selected)?"Русский":t("Системный")); }
        BridgeService.Endpoint peer = BridgeService.client;
        boolean connected = peer != null;
        BridgeService serviceState=BridgeService.instance;
        boolean running = serviceState != null;
        boolean failed = !connected && !bluetoothBusy && running && getSharedPreferences("settings",MODE_PRIVATE).getBoolean("bluetoothWanted",false) && !serviceState.isBluetoothListening();
        if (heroTitle != null) heroTitle.setText(connected ? t("Устройства") : t("Устройства"));
        if (stateBadge != null) { stateBadge.setText(connected ? t("Подключено") : failed ? t("Ошибка соединения") : running ? t("Ожидание Mac") : t("Нет соединения")); stateBadge.setTextColor(connected ? success : failed ? error : bluetoothBusy ? info : running ? warning : muted); }
        if (connection != null) connection.setText(connected ? (peer.isBluetooth() ? t("Подключён по Bluetooth") : t("Подключён через отладку")) : bluetoothBusy || failed ? t(BluetoothLink.status) : running ? t("Ожидание подключения") : t("Соединение отключено"));
        if (bluetoothButton != null) { bluetoothButton.setText(bluetoothBusy ? t("Подключение…") : connected ? t("Отключить Mac") : failed ? t("Повторить запуск") : running ? t("Подключить Mac") : t("Включить соединение")); bluetoothButton.setEnabled(!bluetoothBusy); }
        if(bluetoothButton!=null && !Objects.equals(bluetoothButton.getTag(),connected)) {
            bluetoothButton.setTag(connected); bluetoothButton.setBackground(pressBackground(connected?soft:accent,connected?line:muted));
            bluetoothButton.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{muted,connected?ink:canvas}));
        }
        if (pairButton != null) { pairButton.setVisibility(running && !connected ? View.VISIBLE : View.GONE); pairButton.setEnabled(!bluetoothBusy); }
        if (settingsConnectionState != null) settingsConnectionState.setText(bluetoothBusy || failed ? t(BluetoothLink.status) : connected ? (peer.isBluetooth() ? t("Mac подключён по Bluetooth") : t("Mac подключён через отладку")) : running ? t("Ожидание подключения Mac") : t("Соединение отключено"));
        if (settingsConnectionState != null) settingsConnectionState.setTextColor(connected?success:failed?error:bluetoothBusy?info:running?warning:muted);
        if (bluetoothPermissionRow != null) { boolean allowed=missingBluetoothPermissions(false).length==0; bluetoothPermissionRow.setStatus(allowed?t("Разрешён"):t("Не разрешён"),allowed?success:warning); }
        if (ownNotificationsRow != null) {
            NotificationManager nm=getSystemService(NotificationManager.class); NotificationChannel channel=nm.getNotificationChannel("connection");
            boolean allowed=nm.areNotificationsEnabled(), channelEnabled=channel==null || channel.getImportance()!=NotificationManager.IMPORTANCE_NONE;
            ownNotificationsRow.setStatus(!allowed?t("Отключены"):!channelEnabled?t("Канал отключён"):t("Разрешены"),allowed && channelEnabled?success:warning);
        }
        if (shizukuPermissionRow != null) {
            boolean alive=false,granted=false; try { alive=Shizuku.pingBinder(); granted=alive && Shizuku.checkSelfPermission()==PackageManager.PERMISSION_GRANTED; } catch(RuntimeException ignored) {}
            shizukuPermissionRow.setStatus(!alive?t("Не запущен"):granted?t("Разрешён"):t("Не разрешён"),granted?success:warning);
        }
        if (authorizationRow != null) {
            authorizationRow.setEnabled(!bluetoothBusy);
            int trusted = getSharedPreferences("bluetooth-trust", MODE_PRIVATE).getAll().size();
            authorizationRow.setStatus(trusted == 0 ? t("Нет устройств") : t("Сохранено: ") + trusted);
        }
        if (connectionControlRow != null) { connectionControlRow.setTitle(bluetoothBusy ? t("Запуск соединения…") : failed ? t("Повторить запуск") : running ? t("Отключить соединение") : t("Включить соединение")); connectionControlRow.setEnabled(!bluetoothBusy); }
        if (manualClipboardRow != null) {
            boolean canSend=connected && BridgeService.remoteClipboardEnabled;
            manualClipboardRow.setEnabled(canSend);
            manualClipboardRow.setDetail(!connected ? t("Нет соединения с Mac") : !BridgeService.remoteClipboardEnabled ? t("Буфер отключён на Mac") : "");
        }
        if (notificationPermissionRow != null) {
            boolean access=PhoneNotifications.hasAccess(this);
            notificationPermissionRow.setStatus(access?t("Разрешено"):t("Не разрешено"),access?success:warning);
            notificationPermissionRow.setDetail(access && !PhoneNotifications.isConnected()?t("Служба переподключается"):"",warning);
        }
        if (applicationsRow != null) {
            int excluded=getSharedPreferences("settings",MODE_PRIVATE).getStringSet("blocked",Collections.emptySet()).size();
            applicationsRow.setStatus(excluded==0 ? t("Все") : t("Исключения: ") + excluded);
        }
        if (appearanceRow != null) {
            String appearance=getSharedPreferences("settings",MODE_PRIVATE).getString("appearance","system");
            appearanceRow.setStatus("dark".equals(appearance)?t("Тёмное"):"light".equals(appearance)?t("Светлое"):t("Системное"));
        }
        if (backgroundRow != null) {
            PowerManager power=getSystemService(PowerManager.class);
            boolean unrestricted=power!=null && power.isIgnoringBatteryOptimizations(getPackageName());
            backgroundRow.setStatus(unrestricted ? t("Разрешена") : t("Ограничена"),unrestricted?success:warning);
            backgroundRow.setDetail(unrestricted ? "" : t("Требуется для связи с выключенным экраном"));
        }
        if (pairing != null) { String code = BluetoothLink.PAIRING.display(); pairing.setText(code.isEmpty() ? t("Код не активен") : code.substring(0, 4) + "  " + code.substring(4)); }
        if (clipboardState != null) {
            boolean enabled = getSharedPreferences("settings", MODE_PRIVATE).getBoolean("autoClipboard", false);
            BridgeService service=BridgeService.instance;
            clipboardState.setText(!enabled ? (selectedPage==2 ? t("Для чтения в фоне требуется Shizuku") : t("Автоматическая отправка отключена")) : !connected ? t("Ожидание соединения с Mac") : service!=null && service.clipboard!=null && service.clipboard.isReady() ? t("Shizuku подключён") : t(ClipboardRelay.status));
        }
        if (clipboardState != null) clipboardState.setTextColor(clipboardState.getText().toString().equals(t("Shizuku подключён"))?success:clipboardState.getText().toString().contains(t("Не удалось"))?error:muted);
        if (access != null) {
            boolean forwarding=getSharedPreferences("settings",MODE_PRIVATE).getBoolean("forward",true), granted=PhoneNotifications.hasAccess(this);
            access.setText(!forwarding?t("Отправка приостановлена"):!granted?t("Требуется разрешение Android"):!PhoneNotifications.isConnected()?t("Служба уведомлений переподключается"):t("Передача уведомлений включена"));
            access.setTextColor(!forwarding?muted:granted && PhoneNotifications.isConnected()?success:warning);
        }
    }

    private void showConnectionHelp() {
        new AlertDialog.Builder(this).setTitle(t("Телефон готов к подключению")).setMessage(t("В Conduit на Mac выберите телефон и нажмите «Подключить». Для первой авторизации требуется код."))
            .setNegativeButton(t("Понятно"), null).setPositiveButton(t("Получить код"), (d,w) -> beginBluetooth(true)).show();
    }
    private void showPairingCode() {
        LinearLayout content = column(); content.setPadding(dp(26), dp(12), dp(26), dp(12));
        content.addView(label(t("В Conduit на Mac выберите телефон и введите код:"), 15, false, muted)); gap(content, 24);
        pairing = label("", 32, true, accent); pairing.setTypeface(Typeface.MONOSPACE, Typeface.BOLD); pairing.setGravity(Gravity.CENTER); content.addView(pairing); gap(content, 18);
        content.addView(label(t("Код действует 2 минуты. Устройства должны быть сопряжены в настройках Bluetooth."), 13, false, muted));
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle(t("Связать Mac")).setView(content).setPositiveButton(t("Готово"), null).setNeutralButton(t("Новый код"), null).create();
        dialog.setOnDismissListener(d -> pairing = null); dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> { BluetoothLink.PAIRING.open(); refreshState(); }));
        dialog.show(); refreshState();
    }

    private void chooseFiles() {
        Intent choose = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
        choose.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true); choose.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION); startActivityForResult(choose, 20);
    }
    private void openNotificationAccessSettings() {
        try {
            if(Build.VERSION.SDK_INT>=30) {
                startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,new ComponentName(this,PhoneNotifications.class).flattenToString())); return;
            }
        } catch(ActivityNotFoundException ignored) {}
        startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS));
    }
    private void openApplicationSettings() { startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:"+getPackageName()))); }
    private void configureOwnNotifications() {
        SharedPreferences prefs=getSharedPreferences("settings",MODE_PRIVATE);
        if (Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED &&
            (!prefs.getBoolean("notificationsPermissionRequested",false) || shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))) {
            prefs.edit().putBoolean("notificationsPermissionRequested",true).apply();
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},56);
        } else {
            NotificationChannel channel=getSystemService(NotificationManager.class).getNotificationChannel("connection");
            Intent intent=channel!=null && channel.getImportance()==NotificationManager.IMPORTANCE_NONE ?
                new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID,"connection") : new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
            startActivity(intent.putExtra(Settings.EXTRA_APP_PACKAGE,getPackageName()));
        }
    }
    private void configureShizuku() {
        try {
            if (Shizuku.pingBinder() && Shizuku.checkSelfPermission()!=PackageManager.PERMISSION_GRANTED) { Shizuku.requestPermission(57); return; }
            Intent launch=getPackageManager().getLaunchIntentForPackage("moe.shizuku.privileged.api");
            if(launch!=null) startActivity(launch); else showShizukuHelp();
        } catch(RuntimeException failure) { showShizukuHelp(); }
    }
    private void requestBackground() {
        try {
            PowerManager power = getSystemService(PowerManager.class);
            if (power != null && !power.isIgnoringBatteryOptimizations(getPackageName())) startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + getPackageName())));
            else startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())));
        } catch (RuntimeException failure) { PhoneDiagnostics.record(this, "power.settings.failed", failure); }
    }
    private void copyDiagnostics() {
        ClipData clip = ClipData.newPlainText(t("Conduit — диагностика"), PhoneDiagnostics.report(this));
        PersistableBundle extras = new PersistableBundle(); extras.putBoolean("android.content.extra.IS_SENSITIVE", true); clip.getDescription().setExtras(extras);
        getSystemService(ClipboardManager.class).setPrimaryClip(clip); Toast.makeText(this, t("Диагностика скопирована"), Toast.LENGTH_SHORT).show();
    }
    private void sendClipboard() {
        if (BridgeService.client == null || !BridgeService.remoteClipboardEnabled) { Toast.makeText(this, t("Требуется соединение с Mac и включённый буфер обмена"), Toast.LENGTH_LONG).show(); return; }
        try { ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip(); if (clip != null && clip.getItemCount() > 0) { CharSequence value = clip.getItemAt(0).coerceToText(this); if (value != null) BridgeService.sendClipboard(value.toString()); } }
        catch (RuntimeException failure) { Toast.makeText(this, t("Не удалось прочитать буфер"), Toast.LENGTH_LONG).show(); }
    }
    private void setAutoClipboard(boolean enabled) {
        getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("autoClipboard", enabled).apply();
        if (!enabled) { if (BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.stop(); refreshState(); return; }
        try {
            if (!Shizuku.pingBinder()) { Toast.makeText(this, t("Для автоматической отправки требуется запущенный Shizuku"), Toast.LENGTH_LONG).show(); autoClipboard.setChecked(false); return; }
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) Shizuku.requestPermission(55);
            else if (BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.startIfWanted();
        } catch (RuntimeException failure) { autoClipboard.setChecked(false); }
        refreshState();
    }
    private void disconnect() {
        getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("bluetoothWanted", false).apply();
        startAttempt++; finishBluetoothStart(); stopService(new Intent(this, BridgeService.class)); BluetoothLink.status = t("Bluetooth выключен в Conduit"); refreshState();
    }
    private void forgetMacs() {
        new AlertDialog.Builder(this).setTitle(t("Забыть разрешённые Mac?")).setMessage(t("Для следующего подключения потребуется новый код Conduit.")).setNegativeButton(t("Отмена"), null).setPositiveButton(t("Забыть"), (dialog, which) -> {
            getSharedPreferences("bluetooth-trust", MODE_PRIVATE).edit().clear().commit(); BluetoothLink.PAIRING.close();
            BridgeService.Endpoint peer = BridgeService.client; if (peer != null && peer.isBluetooth()) { BridgeService.deactivate(peer); peer.close(); } refreshState();
        }).show();
    }
    @Override protected void onDestroy() {
        handler.removeCallbacks(update); if (startupTimeout != null) handler.removeCallbacks(startupTimeout);
        Shizuku.removeRequestPermissionResultListener(permissionResult); super.onDestroy();
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        state.putBoolean("discoverAfterPermission", discoverAfterPermission); state.putInt("page", selectedPage); super.onSaveInstanceState(state);
    }
    private void beginBluetooth(boolean discoverable) {
        if (bluetoothBusy) return;
        discoverAfterPermission = discoverable;
        if (discoverable) BluetoothLink.PAIRING.open();
        PhoneDiagnostics.record(this, discoverable ? "start.pair" : "start.manual");
        startBluetooth(discoverable);
    }
    private String[] missingBluetoothPermissions(boolean discoverable) {
        return BluetoothPermissions.missing(Build.VERSION.SDK_INT,
            Build.VERSION.SDK_INT < 31 || checkSelfPermission(BluetoothPermissions.CONNECT) == PackageManager.PERMISSION_GRANTED,
            Build.VERSION.SDK_INT < 31 || checkSelfPermission(BluetoothPermissions.ADVERTISE) == PackageManager.PERMISSION_GRANTED, discoverable);
    }
    private void setBluetoothProgress(String message) {
        bluetoothBusy = true; BluetoothLink.status = message; refreshState();
    }
    private void finishBluetoothStart() {
        bluetoothBusy = false; refreshState();
        if (startupTimeout != null) { handler.removeCallbacks(startupTimeout); startupTimeout = null; }
    }
    private void bluetoothFailure(String message, boolean settings) {
        finishBluetoothStart(); BluetoothLink.status = message; refreshState();
        if (isFinishing() || isDestroyed()) return;
        AlertDialog.Builder dialog = new AlertDialog.Builder(this).setTitle(t("Соединение не запущено")).setMessage(message);
        if (settings) dialog.setPositiveButton(t("Настройки приложения"), (d, w) -> startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()))))
            .setNegativeButton(t("Закрыть"), null);
        else dialog.setPositiveButton(t("Понятно"), null);
        dialog.show();
    }
    private void startBluetooth(boolean discoverable) {
        discoverAfterPermission = discoverable;
        try {
            String[] missing = missingBluetoothPermissions(discoverable);
            if (missing.length != 0) {
                setBluetoothProgress(t("Разреши доступ к устройствам поблизости…"));
                PhoneDiagnostics.record(this, "permission.request"); requestPermissions(missing, 40); return;
            }
            BluetoothManager manager = getSystemService(BluetoothManager.class);
            BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
            if (adapter == null) { bluetoothFailure(t("На телефоне недоступен Bluetooth"), false); return; }
            if (!adapter.isEnabled()) {
                setBluetoothProgress(t("Ожидаю включения Bluetooth…"));
                startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 41); return;
            }
            setBluetoothProgress(t("Запускаю Bluetooth-соединение Conduit…"));
            final int attempt = ++startAttempt;
            startupTimeout = () -> {
                if (attempt != startAttempt || !bluetoothBusy) return;
                PhoneDiagnostics.record(this, "service.start.timeout");
                bluetoothFailure(t("Служба Conduit не ответила за 12 секунд. Нажми «Скопировать диагностику соединения» и пришли результат."), false);
            };
            handler.postDelayed(startupTimeout, 12000);
            ResultReceiver receiver = new ResultReceiver(handler) {
                @Override protected void onReceiveResult(int result, Bundle data) {
                    if (attempt != startAttempt || isDestroyed()) return;
                    finishBluetoothStart();
                    String message = data == null ? t("Не удалось запустить соединение") : data.getString("message", t("Не удалось запустить соединение"));
                    if (result != 1) { bluetoothFailure(message, false); return; }
                    refreshState();
                    Toast.makeText(MainActivity.this, t("Bluetooth-соединение Conduit включено"), Toast.LENGTH_LONG).show();
                    if (discoverable) {
                        showPairingCode();
                        try { startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120), 42); }
                        catch (RuntimeException e) {
                            PhoneDiagnostics.record(MainActivity.this, "discoverable.failed", e);
                            new AlertDialog.Builder(MainActivity.this).setTitle(t("Соединение включено")).setMessage(t("Не удалось открыть обнаружение. Если Mac уже сопряжён с телефоном, можно подключаться по коду Conduit.")).setPositiveButton(t("Понятно"), null).show();
                        }
                    }
                }
            };
            PhoneDiagnostics.record(this, "service.start.request");
            ComponentName component = startForegroundService(new Intent(this, BridgeService.class).setAction("BLUETOOTH_START").putExtra("startupReceiver", receiver));
            if (component == null) bluetoothFailure(t("Android не нашёл службу Conduit. Переустанови обновление приложения."), false);
        } catch (RuntimeException e) {
            PhoneDiagnostics.record(this, "start.failed", e);
            bluetoothFailure(t("Android не разрешил запустить соединение (") + e.getClass().getSimpleName() + t("). Скопируй диагностику соединения."), e instanceof SecurityException);
        }
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if(request==56) { refreshState(); return; }
        if (request == 40) {
            if (missingBluetoothPermissions(discoverAfterPermission).length != 0) {
                PhoneDiagnostics.record(this, grants.length == 0 ? "permission.cancelled" : "permission.denied");
                bluetoothFailure(t("Разреши Conduit доступ к устройствам поблизости в настройках приложения, затем нажми «Включить Bluetooth-соединение» снова."), true);
            } else { PhoneDiagnostics.record(this, "permission.granted"); startBluetooth(discoverAfterPermission); }
        }
    }
    @Override protected void onResume() {
        super.onResume(); PhoneDiagnostics.record(this, "activity.resume"); handler.removeCallbacks(update); update.run();
        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        boolean wanted = prefs.getBoolean("bluetoothWanted", prefs.getBoolean("autoClipboard", false) || !getSharedPreferences("bluetooth-trust", MODE_PRIVATE).getAll().isEmpty());
        if (wanted && BridgeService.instance == null && !bluetoothBusy && missingBluetoothPermissions(false).length == 0) startBluetooth(false);
    }
    @Override protected void onPause() { PhoneDiagnostics.record(this, "activity.pause"); handler.removeCallbacks(update); super.onPause(); }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); handleShare(intent); }
    private void handleShare(Intent intent) {
        if (intent == null) return;
        if (Intent.ACTION_SEND.equals(intent.getAction())) {
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (uri != null && "content".equals(uri.getScheme())) SharedFiles.share(this, uri);
            else Toast.makeText(this, t("Выбери файл или фото. Для текста используй общий буфер."), Toast.LENGTH_LONG).show();
        } else if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
            ArrayList<Uri> uris = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (uris != null) for (Uri uri : uris) if ("content".equals(uri.getScheme())) SharedFiles.share(this, uri);
        }
        intent.setAction(Intent.ACTION_MAIN); // Rotation/recreation must not enqueue the same share again.
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == 41) {
            if (result == RESULT_OK) startBluetooth(discoverAfterPermission);
            else { PhoneDiagnostics.record(this, "bluetooth.enable.cancelled"); bluetoothFailure(t("Bluetooth остался выключенным. Включи его в настройках телефона и повтори."), false); }
            return;
        }
        if (request == 20 && result == RESULT_OK && data != null) {
            if (data.getClipData() != null) for (int i = 0; i < data.getClipData().getItemCount(); i++) SharedFiles.share(this, data.getClipData().getItemAt(i).getUri());
            else if (data.getData() != null) SharedFiles.share(this, data.getData());
        }
    }
    private void chooseApps() {
        List<ResolveInfo> all = getPackageManager().queryIntentActivities(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0);
        TreeMap<String, String> labelsByPackage = new TreeMap<>();
        for (ResolveInfo info : all) if (!info.activityInfo.packageName.equals(getPackageName())) labelsByPackage.put(info.activityInfo.packageName, info.loadLabel(getPackageManager()).toString());
        ArrayList<Map.Entry<String, String>> apps = new ArrayList<>(labelsByPackage.entrySet());
        apps.sort((a, b) -> a.getValue().compareToIgnoreCase(b.getValue()));
        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        Set<String> blocked = new HashSet<>(prefs.getStringSet("blocked", Collections.emptySet()));
        String[] labels = new String[apps.size()]; boolean[] checked = new boolean[apps.size()];
        for (int i = 0; i < apps.size(); i++) { labels[i] = apps.get(i).getValue(); checked[i] = !blocked.contains(apps.get(i).getKey()); }
        new AlertDialog.Builder(this).setTitle(t("Показывать на Mac"))
            .setMultiChoiceItems(labels, checked, (dialog, which, enabled) -> {
                String pkg = apps.get(which).getKey(); if (enabled) blocked.remove(pkg); else blocked.add(pkg);
            }).setPositiveButton(t("Сохранить"), (dialog, which) -> prefs.edit().putStringSet("blocked", blocked).apply())
            .setNegativeButton(t("Отмена"), null).show();
    }
    private LinearLayout column() { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.VERTICAL); return v; }
    private LinearLayout row() { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.HORIZONTAL); v.setGravity(Gravity.CENTER_VERTICAL); return v; }
    private TextView label(String value, int size, boolean bold, int color) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(color);
        view.setTypeface(Typeface.create("sans-serif", bold ? Typeface.BOLD : Typeface.NORMAL)); view.setIncludeFontPadding(false);
        view.setLineSpacing(dp(3), 1); return view;
    }
    private GradientDrawable shape(int color, int radius, boolean border) {
        GradientDrawable drawable = new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(dp(radius)); if (border) drawable.setStroke(dp(1), line); return drawable;
    }
    private LinearLayout card() { LinearLayout view = column(); view.setPadding(dp(22), dp(22), dp(22), dp(22)); view.setBackground(shape(surface, 10, true)); return view; }
    private LinearLayout settingsCard() {
        LinearLayout card=column(); card.setPadding(dp(20),dp(4),dp(20),dp(4)); card.setBackground(shape(surface,10,true)); return card;
    }
    private void rowDivider(LinearLayout parent) {
        View divider=new View(this); divider.setBackgroundColor(line); parent.addView(divider,new LinearLayout.LayoutParams(-1,dp(1)));
    }
    private final class SettingsRow extends LinearLayout {
        private final TextView title,detail,status;
        SettingsRow(LinearLayout parent,String heading,String description,Runnable action,String accessory) {
            super(MainActivity.this); setOrientation(HORIZONTAL); setGravity(Gravity.CENTER_VERTICAL); setMinimumHeight(dp(52));
            setPadding(0,dp(12),0,dp(12)); setBackground(pressBackground(Color.TRANSPARENT,soft));
            LinearLayout words=column(); title=label(heading,14,false,ink); words.addView(title); detail=label("",12,false,muted);
            LinearLayout.LayoutParams detailParams=new LinearLayout.LayoutParams(-1,-2); detailParams.topMargin=dp(4); words.addView(detail,detailParams);
            addView(words,new LinearLayout.LayoutParams(0,-2,1));
            status=label("",12,false,muted); status.setGravity(Gravity.END); status.setMaxWidth(dp(110));
            LinearLayout.LayoutParams statusParams=new LinearLayout.LayoutParams(-2,-2); statusParams.leftMargin=dp(12); addView(status,statusParams);
            if (!accessory.isEmpty()) {
                LinearLayout.LayoutParams iconParams=new LinearLayout.LayoutParams(dp(18),dp(18)); iconParams.leftMargin=dp(10); addView(new IconView(accessory,muted),iconParams);
            }
            setOnClickListener(v->action.run()); setDetail(description); setStatus(""); parent.addView(this,new LinearLayout.LayoutParams(-1,-2));
        }
        void setTitle(String value) { if (!value.contentEquals(title.getText())) title.setText(value); }
        void setStatus(String value) { if (!value.contentEquals(status.getText())) status.setText(value); status.setVisibility(value.isEmpty()?GONE:VISIBLE); }
        void setStatus(String value,int color) { setStatus(value); status.setTextColor(color); }
        void setDetail(String value,int color) { setDetail(value); detail.setTextColor(color); }
        void setDetail(String value) { if (!value.contentEquals(detail.getText())) detail.setText(value); detail.setVisibility(value.isEmpty()?GONE:VISIBLE); }
        @Override public void setEnabled(boolean enabled) { super.setEnabled(enabled); setAlpha(enabled?1f:0.45f); }
    }
    private View iconTile(String icon, int size) {
        IconView view = new IconView(icon, accent); int padding = size <= 32 ? 4 : size < 50 ? 10 : 12; view.setPadding(dp(padding), dp(padding), dp(padding), dp(padding));  return view;
    }
    private Button styledButton(String title, Runnable action, boolean primary) {
        Button button = new Button(this); button.setText(title); button.setAllCaps(false); button.setTextSize(14);
        button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL)); button.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{muted,primary ? canvas : ink}));
        button.setBackground(pressBackground(primary ? accent : soft, primary ? muted : line));
        button.setPadding(dp(17), dp(12), dp(17), dp(12)); button.setMinHeight(dp(48)); button.setMinimumHeight(dp(48)); button.setMinWidth(0); button.setMinimumWidth(0); button.setStateListAnimator(null);
        button.setOnClickListener(v -> action.run()); return button;
    }
    private Button button(LinearLayout parent, String title, Runnable action, boolean primary) {
        Button button = styledButton(title, action, primary); parent.addView(button, new LinearLayout.LayoutParams(-1, -2)); return button;
    }
    private Button smallButton(String title, Runnable action) { return styledButton(title, action, false); }
    private Button textButton(LinearLayout parent, String title, Runnable action) {
        Button b = styledButton(title, action, false); b.setTextColor(accent); b.setBackground(pressBackground(Color.TRANSPARENT, soft));
        parent.addView(b, new LinearLayout.LayoutParams(-1, -2)); return b;
    }
    private StateListDrawable pressBackground(int normal, int pressed) {
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_pressed}, shape(pressed,7,false)); states.addState(new int[]{},shape(normal,7,false)); return states;
    }
    private MinimalSwitch switchRow(LinearLayout parent, String title, boolean checked) {
        MinimalSwitch view = new MinimalSwitch(); view.setText(title); view.setTextSize(15); view.setTextColor(ink); view.setMinHeight(dp(56)); view.setChecked(checked);
        parent.addView(view, new LinearLayout.LayoutParams(-1, -2)); return view;
    }
    private final class MinimalSwitch extends CompoundButton {
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        MinimalSwitch() { super(MainActivity.this); setButtonDrawable(null); setPadding(0, dp(6), dp(62), dp(6)); setGravity(Gravity.CENTER_VERTICAL); setBackground(pressBackground(Color.TRANSPARENT,soft)); }
        @Override public CharSequence getAccessibilityClassName() { return Switch.class.getName(); }
        @Override protected void drawableStateChanged() { super.drawableStateChanged(); invalidate(); }
        @Override protected void onDraw(Canvas c) {
            super.onDraw(c); float right=getWidth()-dp(2), cy=getHeight()/2f;
            paint.setColor(isChecked() ? accent : line); c.drawRoundRect(right-dp(44),cy-dp(13),right,cy+dp(13),dp(13),dp(13),paint);
            paint.setColor(isChecked() ? canvas : surface); c.drawCircle(isChecked() ? right-dp(13) : right-dp(31),cy,dp(10),paint);
        }
    }
    private void heading(String title) { TextView h=label(title,28,true,ink); h.setLetterSpacing(-0.035f); page.addView(h); gap(page,24); }
    private void section(String title) { TextView label=label(title,11,true,muted); label.setLetterSpacing(0.12f); page.addView(label); gap(page,12); }
    private void rule(LinearLayout root) { View rule=new View(this); rule.setBackgroundColor(line); LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(1)); p.topMargin=dp(12); p.bottomMargin=dp(16); root.addView(rule,p); }
    private void gap(LinearLayout root, int height) { root.addView(new View(this), new LinearLayout.LayoutParams(1, dp(height))); }
    private int dp(int size) { return Math.round(size * getResources().getDisplayMetrics().density); }

    private final class IconView extends View {
        final String kind; final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        IconView(String kind,int color) { super(MainActivity.this); this.kind=kind; paint.setColor(color); paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(1.65f); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeJoin(Paint.Join.ROUND); setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); }
        @Override protected void onDraw(Canvas c) {
            super.onDraw(c); c.save();
            float w=getWidth()-getPaddingLeft()-getPaddingRight(), h=getHeight()-getPaddingTop()-getPaddingBottom();
            float scale=Math.min(w,h)/24f; if (scale<=0) { c.restore(); return; }
            c.translate(getPaddingLeft()+(w-24*scale)/2, getPaddingTop()+(h-24*scale)/2); c.scale(scale,scale);
            paint.setStrokeWidth(getResources().getDisplayMetrics().density*1.5f/scale);
            if (kind.equals("mark")) {
                BrandMark.drawTile(c,paint);
            }
            else if (kind.equals("home")) { for(int x=3;x<=14;x+=11) for(int y=3;y<=14;y+=11) c.drawRoundRect(x,y,x+7,y+7,2,2,paint); }
            else if (kind.equals("settings")) { for(int y=5;y<=19;y+=7) { float x=y==12?15:8; c.drawLine(3,y,x-2.5f,y,paint); c.drawLine(x+2.5f,y,21,y,paint); c.drawCircle(x,y,2.5f,paint); } }
            else if (kind.equals("laptop")) { c.drawRoundRect(4,4,20,16,2,2,paint); c.drawLine(2,20,22,20,paint); c.drawLine(4,16,2,20,paint); c.drawLine(20,16,22,20,paint); }
            else if (kind.equals("clipboard")) { c.drawRoundRect(5,5,19,22,2,2,paint); c.drawRoundRect(9,2,15,7,1.5f,1.5f,paint); c.drawLine(9,12,15,12,paint); c.drawLine(9,16,14,16,paint); }
            else if (kind.equals("bell")) { Path p=new Path(); p.moveTo(5,17); p.lineTo(7,14); p.lineTo(7,9); p.cubicTo(7,2,17,2,17,9); p.lineTo(17,14); p.lineTo(19,17); p.close(); c.drawPath(p,paint); c.drawArc(10,17,14,22,0,180,false,paint); }
            else if (kind.equals("upload")) { c.drawRoundRect(5,3,19,22,2,2,paint); c.drawLine(12,16,12,8,paint); c.drawLine(8,12,12,8,paint); c.drawLine(16,12,12,8,paint); }
            else if (kind.equals("copy")) { c.drawRoundRect(8,8,21,21,2,2,paint); Path p=new Path(); p.moveTo(5,16); p.lineTo(3,16); p.lineTo(3,3); p.lineTo(16,3); p.lineTo(16,5); c.drawPath(p,paint); }
            else if (kind.equals("send")) { c.drawLine(5,19,19,5,paint); c.drawLine(9,5,19,5,paint); c.drawLine(19,5,19,15,paint); }
            else if (kind.equals("chevron")) { c.drawLine(9,6,15,12,paint); c.drawLine(15,12,9,18,paint); }
            else { Path p=new Path(); p.moveTo(3,7); p.lineTo(3,20); p.lineTo(21,20); p.lineTo(21,7); p.lineTo(12,7); p.lineTo(10,4); p.lineTo(3,4); p.close(); c.drawPath(p,paint); }
            c.restore();
        }
    }
}
