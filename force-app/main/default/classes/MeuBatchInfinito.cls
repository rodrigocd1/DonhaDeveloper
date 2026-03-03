global class MeuBatchInfinito implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    global Database.QueryLocator start(Database.BatchableContext BC) {
        // Consulta para selecionar uma conta aleatória
        return Database.getQueryLocator('SELECT Id, Name FROM Account LIMIT 1');
    }
    
    global void execute(Database.BatchableContext BC, List<sObject> scope) {
        // Lógica de execução aqui
    }
    
    global void finish(Database.BatchableContext BC) {
        // Chamar o próximo batch imediatamente após a conclusão deste batch
        MeuBatchInfinito proximoBatch = new MeuBatchInfinito();
        Database.executeBatch(proximoBatch);
    }
    
    
       public static void abortarBatches() 
       {
        // Consultar os jobs de batch enfileirados
        List<AsyncApexJob> jobs = [SELECT Id, Status FROM AsyncApexJob WHERE JobType = 'BatchApex' AND Status IN ('Queued', 'Processing')];
        
        // Abortar cada job de batch enfileirado
        for (AsyncApexJob job : jobs) {
            System.abortJob(job.Id);
        }
     }
}