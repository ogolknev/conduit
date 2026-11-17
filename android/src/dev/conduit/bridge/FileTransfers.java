package dev.conduit.bridge;

import java.util.*;

/** Bounded UI state. Names and errors stay out of diagnostics and are not persisted. */
final class FileTransfers {
    enum Phase { PREPARING, WAITING, TRANSFERRING, VERIFYING, COMPLETED, FAILED }
    static final class Entry {
        final String id, name;
        String transport;
        final boolean outgoing;
        Phase phase;
        long total, transferred, started = -1, ended = -1, updated;
        String error;
        Entry(String id, String name, boolean outgoing, String transport, long total, Phase phase, long now) {
            this.id=id; this.name=name; this.outgoing=outgoing; this.transport=transport;
            this.total=total; transferred=0; this.phase=phase; updated=now;
            if (phase==Phase.TRANSFERRING) started=now;
        }
        Entry(Entry entry) {
            this(entry.id,entry.name,entry.outgoing,entry.transport,entry.total,entry.phase,entry.updated);
            transferred=entry.transferred; started=entry.started; ended=entry.ended; error=entry.error;
        }
        boolean active() { return phase!=Phase.COMPLETED && phase!=Phase.FAILED; }
        boolean stalled(long now) { return phase==Phase.TRANSFERRING && now-updated>=5000; }
        long elapsed(long now) { return started<0 ? 0 : Math.max(0,(ended<0?now:ended)-started); }
        double rate(long now) { long time=elapsed(now); return time<=0 || stalled(now) ? 0 : transferred*1000.0/time; }
    }
    private static final LinkedHashMap<String,Entry> entries = new LinkedHashMap<>();
    static long now() { return System.nanoTime()/1_000_000L; }
    static synchronized void begin(String id, String name, boolean outgoing, String transport, long total, Phase phase) {
        entries.remove(id); entries.put(id,new Entry(id,name,outgoing,transport,total,phase,now()));
        while (entries.size()>12) {
            String remove=null;
            for (Entry entry:entries.values()) if (!entry.active()) { remove=entry.id;break; }
            if (remove==null) break; entries.remove(remove);
        }
        while(entries.size()>48)entries.remove(entries.keySet().iterator().next());
    }
    static synchronized void queued(String id, String name, long total) {
        Entry entry=entries.get(id);
        if (entry==null || !entry.active()) begin(id,name,true,"",total,Phase.WAITING);
    }
    static synchronized void phase(String id, Phase phase) {
        Entry entry=entries.get(id);if(entry==null || !entry.active())return;
        entry.phase=phase;if(phase==Phase.TRANSFERRING && entry.started<0){entry.started=now();entry.updated=entry.started;}
    }
    static synchronized void total(String id, long total) {
        Entry entry=entries.get(id);if(entry!=null && entry.active() && total>=entry.transferred)entry.total=total;
    }
    static synchronized void progress(String id, long bytes) {
        Entry entry=entries.get(id);
        if(entry==null || !entry.active() || bytes<entry.transferred || bytes<0 || (entry.total>=0 && bytes>entry.total))return;
        if(bytes>entry.transferred)entry.updated=now();entry.transferred=bytes;
    }
    static synchronized boolean complete(String id) {
        Entry entry=entries.get(id);
        if(entry==null || !entry.active() || entry.total<0 || entry.transferred!=entry.total)return false;
        entry.phase=Phase.COMPLETED;entry.ended=now();return true;
    }
    static synchronized void fail(String id, String error) {
        Entry entry=entries.get(id);if(entry==null || !entry.active())return;
        entry.phase=Phase.FAILED;entry.error=error;entry.ended=now();
    }
    static synchronized List<Entry> snapshot() {
        List<Entry> result=new ArrayList<>();for(Entry entry:entries.values())result.add(new Entry(entry));
        Collections.reverse(result);return result;
    }
    static synchronized void remote(String id, String name, boolean outgoing, long total, Phase phase, long bytes, String error) {
        Entry entry=entries.get(id);
        if(entry==null || (!entry.active() && phase!=Phase.COMPLETED && phase!=Phase.FAILED)) {
            begin(id,name,outgoing,"USB / Wi-Fi",total,Phase.WAITING);entry=entries.get(id);
        }
        entry.transport="USB / Wi-Fi";
        if(total>=0)total(id,total);
        if(phase!=Phase.COMPLETED && phase!=Phase.FAILED)phase(id,phase);
        if(bytes>=0)progress(id,bytes);
        if(phase==Phase.COMPLETED && !complete(id))fail(id,error);
        if(phase==Phase.FAILED)fail(id,error);
    }
}
