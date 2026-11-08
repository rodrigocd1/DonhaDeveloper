/**
 * @lastModified: 2025-05-13 05:02:27
 * @intent: "Provê logging padronizado e estruturado para todo o sistema com rastreabilidade e contexto completo."
 * @exposedTo: [internal]
 * @tags: [logging, platform, structured-data, cross-cutting]
 * @classification: service
 * @description: Sistema de logging estruturado com suporte a contexto, ambiente e categorização.
 * @category: general
 * @type: service
 * @usage: Utilizado por todas as classes do sistema para logging estruturado e rastreável.
 * @note: Implementa padrão fluent interface para configuração de contexto e níveis de log.
 * @stack: apex
 * @scope: public
 * @layer: platform
 * @dependsOn: [FlowExecutionLog__c, LoggerQueueable, Logger, System, EnvironmentUtils, JSON]
 * @gpt: [refactorable, generate-tests, pattern-validation]
 * @name: Logger
 * @author: Leo Garcia
 */

public class Logger {

    //==============================
    // ENUMS
    //==============================
    public enum LogLevel { INFO, WARN, ERROR, SUCCESS }

    //==============================
    // STATIC CONTEXT (Global Config)
    //==============================
    @TestVisible public static String environment = EnvironmentUtils.getRaw() ?? 'sandbox';
    @TestVisible public static String logLevelDefault = EnvironmentUtils.getLogLevel() ?? 'INFO';
    @TestVisible public static final Integer maxDebugLength = (EnvironmentUtils.getMaxDebugLength() != null) ? EnvironmentUtils.getMaxDebugLength() : 3000;

    @TestVisible public static String className;
    @TestVisible public static String triggerType;
    @TestVisible public static String logCategory;
    @TestVisible public static Boolean isEnabled = true;

    //==============================
    // INSTANCE FIELDS (Per-Log Context)
    //==============================
    protected String methodName;
    protected String triggerRecordId;
    protected String instanceEnvironment;
    protected String instanceClassName;
    protected String instanceTriggerType;
    protected String instanceLogCategory;
    protected Exception instanceException;
    protected String instanceLog;
    protected Boolean async = false;
    protected LogLevel logLevel;

    //==============================
    // HTTP-SPECIFIC FIELDS
    //==============================
    protected String methodHttp;
    protected String endpoint;
    protected String reqBody;
    protected Integer statusCode;
    protected String resBody;

    //==============================
    // CONSTRUCTOR
    //==============================
    public Logger() {
        this.instanceClassName   = String.isBlank(className)   ? 'Logger'      : className;
        this.instanceTriggerType = String.isBlank(triggerType) ? 'TestContext' : triggerType;
        this.instanceLogCategory = String.isBlank(logCategory) ? 'General'     : logCategory;
        this.instanceEnvironment = String.isBlank(environment) ? 'sandbox'     : environment;
    }

    //==============================
    // FLUENT SETTERS
    //==============================
    public Logger setMethod(String val)         { this.methodName = val; return this; }
    public Logger setRecordId(String val)       { this.triggerRecordId = val; return this; }
    public Logger setCategory(String val)       { this.instanceLogCategory = val; return this; }
    public Logger setTriggerType(String val)    { this.instanceTriggerType = val; return this; }
    public Logger setEnvironment(String val)    { this.instanceEnvironment = val; return this; }
    public Logger setClass(String val)          { this.instanceClassName = val; return this; }
    public Logger setException(Exception val)   { this.instanceException = val; return this; }
    public Logger setAsync(Boolean val)         { this.async = val; return this; }
    public Logger setLog(String val)            { this.instanceLog = val; return this; }
    public Logger log(String val)               { this.instanceLog = val; return this; }
    public Logger setLogLevel(LogLevel val)     { this.logLevel = val; return this; }
    public Logger setIsEnabled(Boolean val)     { Logger.isEnabled = val; return this; }

    // HTTP-specific setters
    public Logger setMethodHttp(String val)     { this.methodHttp = val; return this; }
    public Logger setEndpoint(String val)       { this.endpoint = val; return this; }
    public Logger setReqBody(String val)        { this.reqBody = val; return this; }
    public Logger setStatus(Integer val)        { this.statusCode = val; return this; }
    public Logger setResBody(String val)        { this.resBody = val; return this; }

    //==============================
    // TERMINAL: CREATE METHODS
    //==============================
    public void create() {
        Logger.LogLevel levelToUse = (this.logLevel != null) ? this.logLevel : Logger.LogLevel.INFO;
        create(levelToUse);
    }

    public void create(Logger.LogLevel level) {
        if (String.isBlank(instanceLog)) return;
        if (String.isNotBlank(methodHttp)) {
            logHttpInternal(level, instanceLog);
        } else {
            logInternal(level, null, null, instanceLog, null, null, null, null, null);
        }
    }

    public void createDebug()   { create(Logger.LogLevel.INFO); }
    public void createInfo()    { create(Logger.LogLevel.INFO); }
    public void createWarn()    { create(Logger.LogLevel.WARN); }
    public void createError()   { create(Logger.LogLevel.ERROR); }
    public void createSuccess() { create(Logger.LogLevel.SUCCESS); }

    //==============================
    // PUBLIC SHORTCUTS
    //==============================
    public void info(String msg)                 { info(msg, null); }
    public void info(String msg, String data)    { logInternal(Logger.LogLevel.INFO, null, null, msg, null, null, null, null, data); }

    public void warn(String msg)                 { warn(msg, null); }
    public void warn(String msg, String data)    { logInternal(Logger.LogLevel.WARN, null, null, msg, null, null, null, null, data); }

    public void success(String msg)              { success(msg, null); }
    public void success(String msg, String data) { logInternal(Logger.LogLevel.SUCCESS, null, null, msg, null, null, null, null, data); }

    public void error(String msg, Exception ex)  { error(msg, ex, null); }
    public void error(String msg, Exception ex, String data) {
        String stack = (ex != null) ? ex.getStackTraceString() : null;
        logInternal(Logger.LogLevel.ERROR, msg, stack, data, null, null, null, null, null);
    }

    public void json(String title, Object payload) {
        String json = (payload != null) ? safeLeft(JSON.serializePretty(payload), 30000) : 'null';
        if (this.methodName == null) this.setMethod('payload');
        if (this.instanceLogCategory == null) this.setCategory('JSON');
        this.info(title, json);
    }

    //==============================
    // HTTP SHORTCUTS
    //==============================
    public void httpInfo(String msg)    { logHttpInternal(Logger.LogLevel.INFO, msg); }
    public void httpWarning(String msg) { logHttpInternal(Logger.LogLevel.WARN, msg); }
    public void httpError(String msg)   { logHttpInternal(Logger.LogLevel.ERROR, msg); }

    //==============================
    // INTERNAL LOG ROUTES
    //==============================
    @TestVisible
    private void logInternal(
        LogLevel level,
        String errorMessage,
        String stackTrace,
        String debugInfo,
        String httpMethod,
        Integer statusCode,
        String requestBody,
        String responseBody,
        String serializedData
    ) {
        logAnyInternal(level, errorMessage, stackTrace, debugInfo, httpMethod, statusCode, requestBody, responseBody, serializedData, null);
    }

    @TestVisible
    private void logHttpInternal(LogLevel level, String msg) {
        logAnyInternal(
            level,
            (level == Logger.LogLevel.ERROR) ? safeLeft(msg, 255) : null,
            (level == Logger.LogLevel.ERROR && instanceException != null) ? instanceException.getStackTraceString() : null,
            this.instanceLog,
            methodHttp,
            statusCode,
            reqBody,
            resBody,
            null,
            endpoint
        );
    }

    private void logAnyInternal(
        LogLevel level,
        String errorMessage,
        String stackTrace,
        String debugInfo,
        String httpMethod,
        Integer statusCode,
        String requestBody,
        String responseBody,
        String serializedData,
        String endpoint
    ) {
        if (!isEnabled && !Test.isRunningTest()) return;

        FlowExecutionLog__c logEntry = new FlowExecutionLog__c(
            Log_Level__c           = level.name(),
            Class__c               = safeLeft(instanceClassName, 255),
            Origin_Method__c       = safeLeft(methodName, 255),
            Trigger_Record_ID__c   = triggerRecordId,
            Error_Message__c       = errorMessage,
            Stack_Trace__c         = safeLeft(stackTrace, 30000),
            Debug_Information__c   = safeLeft(debugInfo, maxDebugLength),
            Serialized_Data__c     = safeLeft(serializedData, 30000),
            MethodHttp__c          = httpMethod,
            StatusCode__c          = (statusCode != null) ? statusCode : 0,
            RequestBody__c         = safeLeft(requestBody, maxDebugLength),
            ResponseBody__c        = safeLeft(responseBody, maxDebugLength),
            Endpoint__c            = safeLeft(endpoint, 255),
            Trigger_Type__c        = instanceTriggerType,
            Log_Category__c        = instanceLogCategory,
            Environment__c         = instanceEnvironment,
            Execution_Timestamp__c = System.now()
        );

        try {
            if (async) {
                System.enqueueJob(new LoggerQueueable(logEntry));
            } else {
                insert logEntry;
            }
        } catch (Exception e) {
            System.debug('[LOGGER FAIL] ' + e.getMessage());
        }
    }

    //==============================
    // UTILS
    //==============================
    @TestVisible
    private static String safeLeft(String val, Integer max) {
        return (val == null) ? null : val.left(max);
    }

    public static Logger fromTrigger(SObject record) {
        Logger log = new Logger();
        if (record != null && record.Id != null) {
            log.setRecordId(record.Id);
        }
        return log;
    }

    //==============================
    // DEFERRED LOGGING BUFFER
    //==============================
    private static List<Logger> deferredLogs = new List<Logger>();

    public static void defer(Logger log) {
        if (log != null) deferredLogs.add(log);
    }

    public static void flush() {
        Integer MAX_FLUSH = Test.isRunningTest() ? 25 : 200; // prevent test chaos
    
        Integer count = 0;
        for (Logger log : deferredLogs) {
            if (log != null && count < MAX_FLUSH) {
                try {
                    log.setAsync(true).create();
                    count++;
                } catch (Exception e) {
                    System.debug('[LOGGER FLUSH ERROR] ' + e.getMessage());
                }
            } else if (count >= MAX_FLUSH) {
                System.debug('[LOGGER FLUSH TRUNCATED] Reached max: ' + MAX_FLUSH);
                break;
            }
        }
    
        deferredLogs.clear();
    }    

    public static void reset() {
        deferredLogs.clear();
    }

}