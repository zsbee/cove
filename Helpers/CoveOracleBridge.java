import java.io.*;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.*;

public class CoveOracleBridge {
    static String read(DataInputStream in) throws IOException {
        int length = in.readInt();
        if (length < 0 || length > 16 * 1024 * 1024) throw new IOException("Invalid request length");
        return new String(in.readNBytes(length), StandardCharsets.UTF_8);
    }
    static String json(String value) {
        if (value == null) return "null";
        StringBuilder out = new StringBuilder("\"");
        for (char c : value.toCharArray()) {
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default: if (c < 32) out.append(String.format("\\u%04x", (int)c)); else out.append(c);
            }
        }
        return out.append('"').toString();
    }
    static void send(String json) throws IOException {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        DataOutputStream out = new DataOutputStream(System.out);
        out.writeInt(bytes.length); out.write(bytes); out.flush();
    }
    public static void main(String[] args) throws Exception {
        DataInputStream input = new DataInputStream(System.in);
        String url = read(input), user = read(input), password = read(input);
        Properties properties = new Properties();
        properties.setProperty("user", user);
        properties.setProperty("password", password);
        properties.setProperty("oracle.jdbc.ReadTimeout", "120000");
        properties.setProperty("oracle.net.CONNECT_TIMEOUT", "15000");
        try (Connection connection = DriverManager.getConnection(url, properties)) {
            connection.setAutoCommit(true);
            send("{\"columns\":[],\"rows\":[],\"affected\":0}");
            while (true) {
                String sql;
                try { sql = read(input); } catch (EOFException eof) { return; }
                try (Statement statement = connection.createStatement()) {
                    statement.setQueryTimeout(120);
                    if (!statement.execute(sql)) {
                        send("{\"columns\":[],\"rows\":[],\"affected\":" + statement.getUpdateCount() + "}");
                        continue;
                    }
                    try (ResultSet rows = statement.getResultSet()) {
                        ResultSetMetaData metadata = rows.getMetaData();
                        int count = metadata.getColumnCount();
                        StringBuilder response = new StringBuilder("{\"columns\":[");
                        for (int i = 1; i <= count; i++) {
                            if (i > 1) response.append(',');
                            response.append("{\"name\":").append(json(metadata.getColumnLabel(i)))
                                .append(",\"type\":").append(json(metadata.getColumnTypeName(i))).append('}');
                        }
                        response.append("],\"rows\":["); boolean first = true;
                        while (rows.next()) {
                            if (!first) response.append(','); first = false; response.append('[');
                            for (int i = 1; i <= count; i++) {
                                if (i > 1) response.append(',');
                                response.append(json(rows.getString(i)));
                            }
                            response.append(']');
                        }
                        send(response.append("]}").toString());
                    }
                } catch (SQLException error) { send("{\"error\":" + json("ORA-" + error.getErrorCode() + ": " + error.getMessage()) + "}"); }
            }
        } catch (SQLException error) {
            send("{\"error\":" + json("ORA-" + error.getErrorCode() + ": " + error.getMessage()) + "}");
        }
    }
}
