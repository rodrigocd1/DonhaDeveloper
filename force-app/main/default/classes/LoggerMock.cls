/**
 * @name: LoggerMock
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: LoggerMock class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

 public class LoggerMock implements ILogger {
    private static List<String> logs = new List<String>();

    public static List<String> getCaptured() {
        return logs;
    }
    public static void clear() {
        logs.clear();
    }

    // Fluent setters
    public ILogger setClass(String val) { return this; }
    public ILogger setMethod(String val) { return this; }
    public ILogger setRecordId(String val) { return this; }
    public ILogger setCategory(String val) { return this; }
    public ILogger setTriggerType(String val) { return this; }
    public ILogger setEnvironment(String val) { return this; }
    public ILogger setAsync(Boolean val) { return this; }

    // Core logs
    public void info(String msg) { logs.add('[INFO] ' + msg); }
    public void info(String msg, String data) { logs.add('[INFO] ' + msg + ' → ' + data); }
    public void warn(String msg) { logs.add('[WARN] ' + msg); }
    public void warn(String msg, String data) { logs.add('[WARN] ' + msg + ' → ' + data); }
    public void success(String msg) { logs.add('[SUCCESS] ' + msg); }
    public void success(String msg, String data) { logs.add('[SUCCESS] ' + msg + ' → ' + data); }
    public void error(String msg, Exception ex) { logs.add('[ERROR] ' + msg + ' → ' + (ex != null ? ex.getMessage() : '')); }
    public void error(String msg, Exception ex, String data) { error(msg, ex); }
    public void json(String title, Object payload) {
        logs.add('[JSON] ' + title + ' → ' + JSON.serialize(payload));
    }

    // HTTP-aware mocks
    public void logHttpInfo(String msg, String methodHttp, String endpoint, String reqBody, Integer status, String resBody) {
        logs.add('[HTTP INFO] ' + msg + ' [' + methodHttp + ' ' + endpoint + '] ' + status);
    }
    public void logHttpWarning(String msg, String methodHttp, String endpoint, String reqBody, Integer status, String resBody) {
        logs.add('[HTTP WARN] ' + msg + ' [' + methodHttp + ' ' + endpoint + '] ' + status);
    }
    public void logHttpError(String msg, Exception ex, String methodHttp, String endpoint, String reqBody, Integer status, String resBody) {
        logs.add('[HTTP ERROR] ' + msg + ' [' + methodHttp + ' ' + endpoint + '] ' + status + ' → ' + (ex != null ? ex.getMessage() : ''));
    }
}