package example;
import org.springframework.stereotype.Service;

@Service
public class Caller {
    private final ServiceTarget target;
    public Caller(ServiceTarget target) { this.target = target; }
    public void run() { target.work(); }
}
