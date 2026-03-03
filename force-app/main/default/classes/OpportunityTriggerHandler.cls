public class OpportunityTriggerHandler { // essa classe comunica com um screen flow e recebe dois parametros da interface do usuário id e installdate
  
    // com esses dados, preciso criar um contrato ou um asset ao clicar num botão de ação rápida
    public class Params {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id oppId;

        @InvocableVariable(label='Install Date' required=true)
        public Date installDate;
    }

    public class Result {
        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Handle Opportunities' description='Handles opportunities after update.')
    public static List<Result> handleOpportunities(List<Params> paramsList) {
        Params params = paramsList[0];  // um set de parametro
        List<Contract> contractsToInsert = new List<Contract>();
        List<Asset> assetsToInsert = new List<Asset>();

        // Oportunidades com RecordTypeID, Oli's, Opp Contact Roles
        Opportunity opp = [SELECT Id, Name, StageName, RecordTypeId, AccountId, Account.Name, ContactId, 
                            //DuracaoContrato__c,
                          (SELECT Id, Product2Id, Product2.Name, OpportunityId FROM OpportunityLineItems),
                          (SELECT ContactId FROM OpportunityContactRoles) FROM Opportunity WHERE Id = :params.oppId];

               
        List<OpportunityFieldHistory> historyList = [SELECT CreatedDate, OldValue, NewValue, Field 
                                                     FROM OpportunityFieldHistory 
                                                     WHERE OpportunityId = :params.oppId 
                                                     AND Field = 'StageName'
                                                     ORDER BY CreatedDate DESC];
                
        Date closedWonDate;
        
        system.debug('===> historyList : ' +  historyList );

        for (OpportunityFieldHistory history : historyList) 
        {
            system.debug('===> OpportunityFieldHistory : ' +  history );
            
            if (history.NewValue == 'Closed Won') 
            {
                closedWonDate = history.CreatedDate.date();
                break;
            }
        }
                       
        // pega os Product2Ids das OLIs depois pega o valor dos campos dos prods
        Set<Id> productIds = new Set<Id>();
        for (OpportunityLineItem oli : opp.OpportunityLineItems) {
            productIds.add(oli.Product2Id);
        }
        
        Map<Id, Product2> products = new Map<Id, Product2>(
            [SELECT Id
            //, Frequencia__c, Validade__c
             FROM Product2 
             WHERE Id IN :productIds]);

        if (opp.StageName == 'Closed Won') {
            for (OpportunityLineItem oli : opp.OpportunityLineItems) {
                if (opp.RecordTypeId != '012as0000001zuHAAQ') { // contrato
                    Contract contract = new Contract();
                    contract.AccountId = opp.AccountId;
                    
                    contract.StartDate = params.installDate; // data de inicio
                    contract.Status = 'Draft';
                    //contract.ContractTerm = (Integer) opp.DuracaoContrato__c; // Prazo do contrato (meses)
                    //contract.Peridiocidade__c = products.get(oli.Product2Id).Frequencia__c; // peridiocidade
                    //contract.Produto__c = oli.Product2Id; // produto vinculado ao contrato
                    //contract.Oportunidade__c = oli.OpportunityId; // oportunidade de origem
                    //contract.ProximaVisita__c = params.installDate.addMonths((Integer) products.get(oli.Product2Id).Frequencia__c);
                    contract.CustomerSignedDate = closedWonDate; //data de assinatura
                    
                    contractsToInsert.add(contract);
                } 
                else if (opp.RecordTypeId != '012as0000001zsfAAA') 
                { //asset
                    Asset asset = new Asset();
                    asset.AccountId = opp.AccountId;
                    asset.ContactId = opp.ContactId;
                    asset.Product2Id = oli.Product2Id;
                    //asset.Oportunidade__c = oli.OpportunityId; // oportunidade
                    asset.InstallDate = params.installDate; // data de instalação
                    asset.PurchaseDate = closedWonDate; // data da compra
                    //asset.UsageEndDate = params.installDate.addMonths((Integer) products.get(oli.Product2Id).Validade__c); // dt término do uso
                    asset.Name = opp.Account.Name + ' - ' + oli.Product2.Name + ' - ' + asset.UsageEndDate;              
                    assetsToInsert.add(asset);
                }
            }
        }
        
        if (!contractsToInsert.isEmpty()) {
            insert contractsToInsert;
        }
        
        if (!assetsToInsert.isEmpty()) {
            insert assetsToInsert;
        }
        
        Result result = new Result();
        result.message = 'Parabéns! A venda foi formalizada com sucesso! Foram criados ' + contractsToInsert.size() + ' contratos e ' + assetsToInsert.size() + ' ativos.';
        return new List<Result> {result};
    }
}