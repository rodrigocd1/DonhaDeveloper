public class GameRestException extends Exception {
    public String errorCode { get; private set; }
    public Integer statusCode { get; private set; }
    public String userMessage { get; private set; }

    public GameRestException(String errorCodeValue, String messageValue, Integer statusCodeValue) {
        this.errorCode = errorCodeValue;
        this.statusCode = statusCodeValue;
        this.userMessage = messageValue;
    }
}
