package dev.conduit.bridge;

import java.io.*;
import java.nio.charset.StandardCharsets;

public final class JsonLineInputTest {
    private static void check(boolean value) { if(!value)throw new AssertionError(); }
    public static void main(String[] args) throws Exception {
        byte[] frames=("{\"type\":\"hello\"}\n{\"text\":\"Привет\"}\n").getBytes(StandardCharsets.UTF_8);
        final int[] reads={0};
        InputStream source=new ByteArrayInputStream(frames) {
            @Override public synchronized int read(byte[] bytes,int offset,int length) { reads[0]++;return super.read(bytes,offset,length); }
        };
        JsonLineInput input=new JsonLineInput(source);
        check(input.readLine(4096).equals("{\"type\":\"hello\"}"));
        check(input.readLine(4096).equals("{\"text\":\"Привет\"}"));
        check(reads[0]==1); // Readahead survives the authentication/frame boundary.
        JsonLineInput fragmented=new JsonLineInput(new ByteArrayInputStream(frames) {
            @Override public synchronized int read(byte[] bytes,int offset,int length) { return super.read(bytes,offset,Math.min(2,length)); }
        });
        check(fragmented.readLine(4096).equals("{\"type\":\"hello\"}"));
        check(fragmented.readLine(4096).equals("{\"text\":\"Привет\"}"));
        check(new JsonLineInput(new ByteArrayInputStream("123\n".getBytes())).readLine(3).equals("123"));
        try { new JsonLineInput(new ByteArrayInputStream("1234\n".getBytes())).readLine(3);throw new AssertionError(); }catch(IOException expected){}
        try { new JsonLineInput(new ByteArrayInputStream("partial".getBytes())).readLine(100);throw new AssertionError(); }catch(EOFException expected){}
        System.out.println("JSON line input: buffered reads, frame boundaries, fragmented UTF-8, size bounds and truncated EOF passed");
    }
}
