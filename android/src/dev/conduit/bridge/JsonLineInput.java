package dev.conduit.bridge;

import java.io.*;

/** One reader per connection, retained across authentication and later frames. */
final class JsonLineInput {
    private final BufferedInputStream input;
    JsonLineInput(InputStream input) { this.input=new BufferedInputStream(input,65536); }
    String readLine(int limit) throws IOException {
        ByteArrayOutputStream line=new ByteArrayOutputStream();int next;
        while((next=input.read())!=-1) {
            if(next=='\n')return line.toString("UTF-8");
            if(line.size()>=limit)throw new IOException("Frame too long");
            line.write(next);
        }
        throw new EOFException();
    }
}
