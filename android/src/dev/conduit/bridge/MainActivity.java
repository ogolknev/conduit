package dev.conduit.bridge;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import rikka.shizuku.Shizuku;
import android.content.*;
import android.content.pm.*;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import java.util.*;

public final class MainActivity extends Activity {
    private TextView connection, access, pairing, clipboardState, backgroundState;
    private Button bluetoothButton, pairButton;
    private Switch autoClipboard;
    private boolean discoverAfterPermission, bluetoothBusy;
    private int startAttempt;
    private Runnable startupTimeout;
    private final Shizuku.OnRequestPermissionResultListener permissionResult = (code, grant) -> {
        if (code != 55) return;
        getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("autoClipboard", grant == PackageManager.PERMISSION_GRANTED).apply();
        if (grant == PackageManager.PERMISSION_GRANTED && BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.startIfWanted();
        if (autoClipboard != null) autoClipboard.setChecked(grant == PackageManager.PERMISSION_GRANTED);
    };
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable update = new Runnable() {
        @Override public void run() {
            if (connection != null) connection.setText(BridgeService.client != null ? (BridgeService.client.isBluetooth() ? "Mac подключён по Bluetooth" : "Mac подключён через отладку") : BluetoothLink.status);
            if (pairing != null) { String code = BluetoothLink.PAIRING.display(); pairing.setText(code.isEmpty() ? "Код не активен" : "Код Conduit: " + code + " · 2 минуты"); }
            if (clipboardState != null) clipboardState.setText(ClipboardRelay.status);
            if (backgroundState != null) {
                PowerManager power = getSystemService(PowerManager.class);
                backgroundState.setText(power != null && power.isIgnoringBatteryOptimizations(getPackageName()) ? "Фоновая работа без экономии батареи разрешена" : "Фоновая работа ограничена экономией батареи");
            }
            if (access != null) access.setText(PhoneNotifications.hasAccess(MainActivity.this) ? "Доступ к уведомлениям разрешён" : "Разреши доступ, чтобы видеть уведомления на Mac");
            handler.postDelayed(this, 2000);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) discoverAfterPermission = state.getBoolean("discoverAfterPermission");
        PhoneDiagnostics.record(this, "activity.open");
        getWindow().setStatusBarColor(Color.rgb(245, 248, 248));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(40), dp(24), dp(24)); root.setBackgroundColor(Color.rgb(245, 248, 248));
        scroll.addView(root); setContentView(scroll);
        TextView title = text("Conduit", 34); title.setTypeface(null, Typeface.BOLD); root.addView(title);
        root.addView(text("Твой Android. Рядом с Mac.", 17));
        try { root.addView(text("Версия " + getPackageManager().getPackageInfo(getPackageName(), 0).versionName, 13)); }
        catch (PackageManager.NameNotFoundException ignored) {}
        gap(root, 26);
        connection = text("Ожидаю Conduit на Mac", 20); connection.setTypeface(null, Typeface.BOLD); root.addView(connection);
        root.addView(text("Включи соединение ниже, свяжи телефон и Mac в настройках Bluetooth, затем выбери телефон в Conduit на Mac.", 15));
        bluetoothButton = button(root, "Включить Bluetooth-соединение", () -> beginBluetooth(false));
        pairButton = button(root, "Связать новый Mac", () -> beginBluetooth(true));
        button(root, "Скопировать диагностику соединения", () -> {
            ClipData clip = ClipData.newPlainText("Conduit — диагностика", PhoneDiagnostics.report(this));
            PersistableBundle extras = new PersistableBundle(); extras.putBoolean("android.content.extra.IS_SENSITIVE", true); clip.getDescription().setExtras(extras);
            getSystemService(ClipboardManager.class).setPrimaryClip(clip);
            Toast.makeText(this, "Диагностика скопирована", Toast.LENGTH_SHORT).show();
        });
        backgroundState = text("", 14); root.addView(backgroundState);
        button(root, "Разрешить фоновую работу", () -> {
            try {
                PowerManager power = getSystemService(PowerManager.class);
                if (power != null && !power.isIgnoringBatteryOptimizations(getPackageName()))
                    startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + getPackageName())));
                else startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())));
            } catch (RuntimeException failure) { PhoneDiagnostics.record(this, "power.settings.failed", failure); }
        });
        root.addView(text("Для связи с выключенным экраном разреши фоновую работу. Пока Mac подключён, Conduit поддерживает работу процессора. Журнал автоматически передаётся на Mac при подключении; текст буфера в него не входит.", 14));
        pairing = text("Код не активен", 20); pairing.setTypeface(Typeface.MONOSPACE, Typeface.BOLD); root.addView(pairing);
        root.addView(text("Введи код Conduit на Mac после системного сопряжения Bluetooth. При следующих подключениях код не нужен.", 14));
        button(root, "Забыть разрешённые Mac", () -> new AlertDialog.Builder(this).setTitle("Удалить связи Conduit?").setMessage("Для нового подключения потребуется код с этого экрана.")
            .setNegativeButton("Отмена", null).setPositiveButton("Забыть", (dialog, which) -> {
                getSharedPreferences("bluetooth-trust", MODE_PRIVATE).edit().clear().commit(); BluetoothLink.PAIRING.close();
                BridgeService.Endpoint peer = BridgeService.client; if (peer != null && peer.isBluetooth()) { BridgeService.deactivate(peer); peer.close(); }
            }).show());
        gap(root, 26);
        root.addView(text("Уведомления", 22));
        access = text("", 15); root.addView(access);
        button(root, "Разрешить доступ к уведомлениям", () -> startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)));
        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        Switch forwarding = new Switch(this); forwarding.setText("Показывать уведомления на Mac");
        forwarding.setChecked(prefs.getBoolean("forward", true));
        forwarding.setOnCheckedChangeListener((view, checked) -> prefs.edit().putBoolean("forward", checked).apply()); root.addView(forwarding);
        button(root, "Выбрать приложения", this::chooseApps);
        root.addView(text("Ответить с Mac можно, если само уведомление поддерживает быстрый ответ. Защищённое содержимое Android может скрывать.", 14));
        gap(root, 26);
        root.addView(text("Файлы", 22));
        button(root, "Отправить файл на Mac", () -> {
            Intent choose = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
            choose.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
            choose.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION); startActivityForResult(choose, 20);
        });
        root.addView(text("Или выбери «Поделиться» → Conduit в любом приложении. Очередь — до 1 ГБ, 32 файла.", 14));
        gap(root, 26);
        root.addView(text("Буфер обмена", 22));
        root.addView(text("Mac → телефон: новые копирования приходят автоматически. Для автоматической отправки с телефона включи Shizuku ниже.", 15));
        autoClipboard = new Switch(this); autoClipboard.setText("Автобуфер через Shizuku");
        autoClipboard.setChecked(prefs.getBoolean("autoClipboard", false));
        autoClipboard.setOnCheckedChangeListener((view, enabled) -> {
            prefs.edit().putBoolean("autoClipboard", enabled).apply();
            if (!enabled) { if (BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.stop(); return; }
            try {
                if (!Shizuku.pingBinder()) { Toast.makeText(this, "Установи и запусти Shizuku, затем включи автобуфер снова", Toast.LENGTH_LONG).show(); autoClipboard.setChecked(false); return; }
                if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) Shizuku.requestPermission(55);
                else if (BridgeService.instance != null && BridgeService.instance.clipboard != null) BridgeService.instance.clipboard.startIfWanted();
            } catch (Exception e) { autoClipboard.setChecked(false); }
        }); root.addView(autoClipboard);
        clipboardState = text(ClipboardRelay.status, 14); root.addView(clipboardState);
        button(root, "Отправить скопированный текст", () -> {
            if (BridgeService.client == null || !BridgeService.remoteClipboardEnabled) { Toast.makeText(this, "Подключи Mac и включи общий буфер", Toast.LENGTH_LONG).show(); return; }
            try {
                ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
                if (clip != null && clip.getItemCount() > 0) { CharSequence value = clip.getItemAt(0).coerceToText(this); if (value != null) BridgeService.sendClipboard(value.toString()); }
            } catch (Exception e) { Toast.makeText(this, "Не удалось прочитать буфер", Toast.LENGTH_LONG).show(); }
        });
        root.addView(text("Без root Shizuku нужно снова запускать после перезагрузки телефона. Общий буфер можно приостановить в Conduit на Mac.", 14));
        gap(root, 26);
        button(root, "Отключить соединение Conduit", () -> {
            getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("bluetoothWanted", false).apply();
            startAttempt++; finishBluetoothStart(); stopService(new Intent(this, BridgeService.class));
            BluetoothLink.status = "Bluetooth выключен в Conduit"; connection.setText(BluetoothLink.status);
        });
        root.addView(text("После перезагрузки телефона открой Conduit и включи Bluetooth-соединение. Автобуфер отдельно требует запущенного Shizuku.", 14));
        Shizuku.addRequestPermissionResultListener(permissionResult);
        handleShare(getIntent());
    }
    @Override protected void onDestroy() {
        handler.removeCallbacks(update); if (startupTimeout != null) handler.removeCallbacks(startupTimeout);
        Shizuku.removeRequestPermissionResultListener(permissionResult); super.onDestroy();
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        state.putBoolean("discoverAfterPermission", discoverAfterPermission); super.onSaveInstanceState(state);
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
        bluetoothBusy = true; bluetoothButton.setEnabled(false); pairButton.setEnabled(false);
        BluetoothLink.status = message; connection.setText(message);
    }
    private void finishBluetoothStart() {
        bluetoothBusy = false; bluetoothButton.setEnabled(true); pairButton.setEnabled(true);
        if (startupTimeout != null) { handler.removeCallbacks(startupTimeout); startupTimeout = null; }
    }
    private void bluetoothFailure(String message, boolean settings) {
        finishBluetoothStart(); BluetoothLink.status = message; connection.setText(message);
        if (isFinishing() || isDestroyed()) return;
        AlertDialog.Builder dialog = new AlertDialog.Builder(this).setTitle("Соединение не запущено").setMessage(message);
        if (settings) dialog.setPositiveButton("Настройки приложения", (d, w) -> startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()))))
            .setNegativeButton("Закрыть", null);
        else dialog.setPositiveButton("Понятно", null);
        dialog.show();
    }
    private void startBluetooth(boolean discoverable) {
        discoverAfterPermission = discoverable;
        try {
            String[] missing = missingBluetoothPermissions(discoverable);
            if (missing.length != 0) {
                setBluetoothProgress("Разреши доступ к устройствам поблизости…");
                PhoneDiagnostics.record(this, "permission.request"); requestPermissions(missing, 40); return;
            }
            BluetoothManager manager = getSystemService(BluetoothManager.class);
            BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
            if (adapter == null) { bluetoothFailure("На телефоне недоступен Bluetooth", false); return; }
            if (!adapter.isEnabled()) {
                setBluetoothProgress("Ожидаю включения Bluetooth…");
                startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 41); return;
            }
            setBluetoothProgress("Запускаю Bluetooth-соединение Conduit…");
            final int attempt = ++startAttempt;
            startupTimeout = () -> {
                if (attempt != startAttempt || !bluetoothBusy) return;
                PhoneDiagnostics.record(this, "service.start.timeout");
                bluetoothFailure("Служба Conduit не ответила за 12 секунд. Нажми «Скопировать диагностику соединения» и пришли результат.", false);
            };
            handler.postDelayed(startupTimeout, 12000);
            ResultReceiver receiver = new ResultReceiver(handler) {
                @Override protected void onReceiveResult(int result, Bundle data) {
                    if (attempt != startAttempt || isDestroyed()) return;
                    finishBluetoothStart();
                    String message = data == null ? "Не удалось запустить соединение" : data.getString("message", "Не удалось запустить соединение");
                    if (result != 1) { bluetoothFailure(message, false); return; }
                    connection.setText(BluetoothLink.status);
                    Toast.makeText(MainActivity.this, "Bluetooth-соединение Conduit включено", Toast.LENGTH_LONG).show();
                    if (discoverable) {
                        try { startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120), 42); }
                        catch (RuntimeException e) {
                            PhoneDiagnostics.record(MainActivity.this, "discoverable.failed", e);
                            new AlertDialog.Builder(MainActivity.this).setTitle("Соединение включено").setMessage("Не удалось открыть обнаружение. Если Mac уже сопряжён с телефоном, можно подключаться по коду Conduit.").setPositiveButton("Понятно", null).show();
                        }
                    }
                }
            };
            PhoneDiagnostics.record(this, "service.start.request");
            ComponentName component = startForegroundService(new Intent(this, BridgeService.class).setAction("BLUETOOTH_START").putExtra("startupReceiver", receiver));
            if (component == null) bluetoothFailure("Android не нашёл службу Conduit. Переустанови обновление приложения.", false);
        } catch (RuntimeException e) {
            PhoneDiagnostics.record(this, "start.failed", e);
            bluetoothFailure("Android не разрешил запустить соединение (" + e.getClass().getSimpleName() + "). Скопируй диагностику соединения.", e instanceof SecurityException);
        }
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if (request == 40) {
            if (missingBluetoothPermissions(discoverAfterPermission).length != 0) {
                PhoneDiagnostics.record(this, grants.length == 0 ? "permission.cancelled" : "permission.denied");
                bluetoothFailure("Разреши Conduit доступ к устройствам поблизости в настройках приложения, затем нажми «Включить Bluetooth-соединение» снова.", true);
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
            else Toast.makeText(this, "Выбери файл или фото. Для текста используй общий буфер.", Toast.LENGTH_LONG).show();
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
            else { PhoneDiagnostics.record(this, "bluetooth.enable.cancelled"); bluetoothFailure("Bluetooth остался выключенным. Включи его в настройках телефона и повтори.", false); }
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
        new AlertDialog.Builder(this).setTitle("Показывать на Mac")
            .setMultiChoiceItems(labels, checked, (dialog, which, enabled) -> {
                String pkg = apps.get(which).getKey(); if (enabled) blocked.remove(pkg); else blocked.add(pkg);
            }).setPositiveButton("Сохранить", (dialog, which) -> prefs.edit().putStringSet("blocked", blocked).apply())
            .setNegativeButton("Отмена", null).show();
    }
    private TextView text(String value, int size) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(Color.rgb(30, 46, 48));
        view.setPadding(0, dp(5), 0, dp(8)); return view;
    }
    private Button button(LinearLayout root, String label, Runnable action) {
        Button button = new Button(this); button.setText(label); button.setAllCaps(false);
        button.setOnClickListener(view -> action.run()); root.addView(button, new LinearLayout.LayoutParams(-1, -2)); return button;
    }
    private void gap(LinearLayout root, int height) { View gap = new View(this); root.addView(gap, new LinearLayout.LayoutParams(1, dp(height))); }
    private int dp(int size) { return Math.round(size * getResources().getDisplayMetrics().density); }
}
