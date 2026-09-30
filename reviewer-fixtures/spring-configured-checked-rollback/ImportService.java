import java.io.IOException;
import org.springframework.stereotype.Service;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ImportService {
    private final JdbcTemplate jdbc;
    public ImportService(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    @Transactional
    public void importData() throws IOException {
        jdbc.update("INSERT INTO imports (state) VALUES (?)", "started");
        throw new IOException("Source unavailable");
    }
}
