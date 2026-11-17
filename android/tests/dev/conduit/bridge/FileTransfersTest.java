package dev.conduit.bridge;

import java.util.*;

public final class FileTransfersTest {
    private static void check(boolean value) { if(!value)throw new AssertionError(); }
    private static FileTransfers.Entry entry(String id) { for(FileTransfers.Entry e:FileTransfers.snapshot())if(e.id.equals(id))return e;throw new AssertionError(); }
    public static void main(String[] args) {
        FileTransfers.begin("first","Example.bin",false,"Bluetooth",100,FileTransfers.Phase.TRANSFERRING);
        FileTransfers.progress("first",40);check(entry("first").transferred==40);
        FileTransfers.progress("first",30);FileTransfers.progress("first",101);check(entry("first").transferred==40);
        check(!FileTransfers.complete("first"));FileTransfers.progress("first",100);
        FileTransfers.phase("first",FileTransfers.Phase.VERIFYING);check(entry("first").active());
        check(FileTransfers.complete("first"));FileTransfers.fail("first","Late error");check(entry("first").phase==FileTransfers.Phase.COMPLETED);
        FileTransfers.begin("failed","Example.bin",true,"Bluetooth",100,FileTransfers.Phase.WAITING);
        FileTransfers.fail("failed","Disconnected");FileTransfers.progress("failed",100);FileTransfers.phase("failed",FileTransfers.Phase.TRANSFERRING);
        check(!entry("failed").active() && entry("failed").transferred==0 && !FileTransfers.complete("failed"));
        FileTransfers.begin("empty","Empty.bin",true,"Bluetooth",0,FileTransfers.Phase.VERIFYING);check(FileTransfers.complete("empty"));
        FileTransfers.begin("unknown","Stream",true,"",-1,FileTransfers.Phase.PREPARING);check(!FileTransfers.complete("unknown"));
        FileTransfers.Entry snapshot=entry("unknown");snapshot.total=10;check(entry("unknown").total==-1);
        FileTransfers.total("unknown",20);FileTransfers.progress("unknown",20);check(FileTransfers.complete("unknown"));
        FileTransfers.Entry timing=new FileTransfers.Entry("timer","Example.bin",true,"Bluetooth",1000,FileTransfers.Phase.TRANSFERRING,1000);
        timing.transferred=400;timing.updated=3000;check(timing.rate(3000)==200);check(timing.stalled(8000) && timing.rate(8000)==0);
        for(int i=0;i<20;i++){String id="done-"+i;FileTransfers.begin(id,"Empty",false,"",0,FileTransfers.Phase.VERIFYING);FileTransfers.complete(id);}
        check(FileTransfers.snapshot().size()<=12);
        FileTransfers.queued("remote","Example.bin",100);
        FileTransfers.remote("remote","Example.bin",true,100,FileTransfers.Phase.TRANSFERRING,50,null);
        check(entry("remote").transferred==50 && entry("remote").transport.equals("USB / Wi-Fi"));
        FileTransfers.remote("remote","Example.bin",true,100,FileTransfers.Phase.COMPLETED,90,"Not confirmed");
        check(entry("remote").phase==FileTransfers.Phase.FAILED);
        FileTransfers.remote("remote","Example.bin",true,100,FileTransfers.Phase.TRANSFERRING,0,null);
        FileTransfers.remote("remote","Example.bin",true,100,FileTransfers.Phase.COMPLETED,100,null);
        check(entry("remote").phase==FileTransfers.Phase.COMPLETED);
        System.out.println("File transfers: monotonic progress, confirmation, failure, empty/unknown sizes, snapshots, rate/stall and bounded history passed");
    }
}
