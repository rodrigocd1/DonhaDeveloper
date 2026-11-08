public class TotemLeadDeliveryResult {
    public Boolean success { get; private set; }
    public String category { get; private set; }

    private TotemLeadDeliveryResult(Boolean success, String category) {
        this.success = success;
        this.category = category;
    }

    public static TotemLeadDeliveryResult succeeded() {
        return new TotemLeadDeliveryResult(true, null);
    }

    public static TotemLeadDeliveryResult failed(String category) {
        return new TotemLeadDeliveryResult(false, category);
    }
}