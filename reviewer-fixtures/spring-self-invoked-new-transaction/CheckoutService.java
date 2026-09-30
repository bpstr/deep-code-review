import org.springframework.stereotype.Service;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Propagation;

@Service
public class CheckoutService {
    private final JdbcTemplate jdbc;
    public CheckoutService(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    @Transactional
    public void place() {
        audit();
        throw new IllegalStateException("Order rejected");
    }
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void audit() {
        jdbc.update("INSERT INTO audit_log (message) VALUES (?)", "checkout attempted");
    }
}
