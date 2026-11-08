/**
 * @name: LoggerQueueable
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: LoggerQueueable class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

 public without sharing class LoggerQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible private static final Integer CHUNK_SIZE = 10;
    @TestVisible public List<FlowExecutionLog__c> logs;

    public LoggerQueueable(FlowExecutionLog__c log) {
        this.logs = log != null ? new List<FlowExecutionLog__c>{ log } : new List<FlowExecutionLog__c>();
    }

    public LoggerQueueable(List<FlowExecutionLog__c> logs) {
        this.logs = logs != null ? logs : new List<FlowExecutionLog__c>();
    }

    public void execute(QueueableContext context) {
        if (this.logs == null) {
            this.logs = new List<FlowExecutionLog__c>();
        }

        if (logs.isEmpty() || !EnvironmentUtils.isLogAtivo()) return;

        Integer total = logs.size();
        Integer i = 0;
        while (i < total) {
            List<FlowExecutionLog__c> chunk = new List<FlowExecutionLog__c>();
            for (Integer j = i; j < Math.min(i + CHUNK_SIZE, total); j++) {
                chunk.add(logs[j]);
            }
            if (!chunk.isEmpty()) insert chunk;
            i += CHUNK_SIZE;
        }
    }
}