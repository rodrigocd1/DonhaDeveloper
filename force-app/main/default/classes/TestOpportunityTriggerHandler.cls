@IsTest (seeAllData=true)
private class TestOpportunityTriggerHandler {

    // Método de teste para verificar a criação de Contratos e Ativos quando a Opportunity está fechada e ganha
    static testMethod void testHandleOpportunitiesClosedWon() {
        // Criar dados de teste para Account e Contact
        Account testAccount = new Account(Name='Test Account');
        insert testAccount;

        Contact testContact = new Contact(LastName='Test Contact', AccountId=testAccount.Id);
        insert testContact;

        // Garantir que existe um PriceBook padrão e ativo
        Pricebook2 standardPriceBook = new Pricebook2(Name='Standard Price Book', IsActive=true);
        insert standardPriceBook;

        update standardPriceBook;

        standardPricebook = [SELECT IsStandard FROM Pricebook2 WHERE Id = :standardPricebook.Id];

        Pricebook2 standardPB = [select id from Pricebook2 where isStandard = true];

        // Criar um PriceBookEntry para o Product2
        Product2 testProduct = new Product2(Name='Test Product');
        insert testProduct;

        PricebookEntry standardPriceBookEntry = new PricebookEntry(
            Pricebook2Id=standardPB.Id,
            Product2Id=testProduct.Id,
            UnitPrice=100,
            IsActive=true
        );
        insert standardPriceBookEntry;

        // Criar a Opportunity com referência ao PriceBook
        Opportunity testOpportunity = new Opportunity(
            Name='Test Opportunity',
            AccountId=testAccount.Id,
            StageName='Closed Won',
            CloseDate=Date.today(),
            Pricebook2Id=standardPB.Id
           // , RecordTypeId='012as0000001zuHAAQ' // Ajustar conforme o RecordTypeId real
        );
        insert testOpportunity;
              

        // Criar a OpportunityLineItem com referência ao PriceBookEntry
        OpportunityLineItem testOli = new OpportunityLineItem(
            OpportunityId=testOpportunity.Id,
            Product2Id=testProduct.Id,
            Quantity=1,
            TotalPrice=100,
            PricebookEntryId=standardPriceBookEntry.Id
        );
        insert testOli;

        // Configurar parâmetros de entrada para o método de tratamento
        OpportunityTriggerHandler.Params testParams = new OpportunityTriggerHandler.Params();
        testParams.oppId = testOpportunity.Id;
        testParams.installDate = Date.today();

        List<OpportunityTriggerHandler.Params> paramsList = new List<OpportunityTriggerHandler.Params>{testParams};

        testOpportunity.StageName = 'Closed Won';
        update testOpportunity;
        
        testOpportunity.StageName = 'Negotiation/Review';
        update testOpportunity;
        
        testOpportunity.StageName = 'Closed Won';
        update testOpportunity;
        
        
        // Chamar o método de tratamento
        Test.startTest();        
        List<OpportunityTriggerHandler.Result> results = OpportunityTriggerHandler.handleOpportunities(paramsList);
        Test.stopTest();

        // Verificar resultados
        System.assertEquals(1, results.size(), 'Deve retornar um resultado');
        System.assert(results[0].message.contains('Parabéns!'), 'A mensagem deve conter felicitações');

        // Verificar criação de contratos e/ou ativos
        List<Contract> contracts = [SELECT Id FROM Contract WHERE AccountId = :testAccount.Id];
        List<Asset> assets = [SELECT Id FROM Asset WHERE AccountId = :testAccount.Id];

        System.assertEquals(1, contracts.size(), 'Deve criar um contrato');
        System.assertEquals(0, assets.size(), 'Não deve criar ativos neste cenário específico');
    }
   
   /*
    @IsTest
    static void testCreateContract() {
        // Crie um registro de teste para Account
        Account acc = new Account(Name='Test Account');
        insert acc;

        // Crie um registro de teste para Contact
        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc.Id);
        insert con;

        // Crie um registro de teste para Product2 do tipo Contrato
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true
                                    //, Frequencia__c = 1, Validade__c = 12, TipoProduto__c = 'Contrato'
                                    );
        insert prod;

        // Crie um registro de teste para Opportunity com RecordTypeId do tipo Contrato
        Opportunity opp = new Opportunity(Name='Test Opportunity', 
                                          StageName='Needs Analysis', 
                                          CloseDate=Date.today(), 
                                          AccountId=acc.Id, 
                                          ContactId=con.Id, 
                                          RecordTypeId='012as0000001zuHAAQ');
        insert opp;
        
        // Altere um campo na Opportunity
         opp.StageName = 'Closed Won';
         update opp; 

        // Crie um registro de teste para OpportunityLineItem
        Pricebook2 stdPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true];
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPricebook.Id, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;
        OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = pbe.Id, Quantity = 1, TotalPrice = 100);
        insert oli;

        // Chame o método handleOpportunities
        OpportunityTriggerHandler.Params params = new OpportunityTriggerHandler.Params();
        params.oppId = opp.Id;
        params.installDate = Date.today();
        List<OpportunityTriggerHandler.Params> paramsList = new List<OpportunityTriggerHandler.Params>{params};
        Test.startTest();
            List<OpportunityTriggerHandler.Result> results = OpportunityTriggerHandler.handleOpportunities(paramsList);
        Test.stopTest();

        // Verifique se um Contract foi criado
       // List<Contract> contracts = [SELECT Id FROM Contract WHERE Oportunidade__c = :opp.Id];
        //System.assertEquals(1, contracts.size(), 'Expected one Contract to be created');

    }

    @IsTest
    static void testOpportunityHistoricFields() { // ESSE É O MÉTODO QUE PRECISO DE AJUDA
        Account acc = new Account(Name='Test Account');
        insert acc;

        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc.Id);
        insert con;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true
        //, Frequencia__c = 1, Validade__c = 12, TipoProduto__c = 'Contrato'
        );
        insert prod;

        Opportunity opp = new Opportunity(Name='Test Opportunity', 
                                          StageName='Needs Analysis', 
                                          CloseDate=Date.today(), 
                                          AccountId=acc.Id, 
                                          ContactId=con.Id, 
                                          RecordTypeId='012as0000001zuHAAQ');
        insert opp;

        Test.startTest();
            opp.StageName = 'Closed Won';
            update opp;
        Test.stopTest();

        // Call the method to be tested
        OpportunityTriggerHandler.Params params = new OpportunityTriggerHandler.Params();
        params.oppId = opp.Id;
        params.installDate = Date.today();
        List<OpportunityTriggerHandler.Params> paramsList = new List<OpportunityTriggerHandler.Params>{params};
        List<OpportunityTriggerHandler.Result> results = OpportunityTriggerHandler.handleOpportunities(paramsList);

        // Verify the results
        List<OpportunityFieldHistory> historyRecords = [SELECT OldValue, NewValue, Field 
                                                        FROM OpportunityFieldHistory 
                                                        WHERE OpportunityId = :opp.Id];
        System.assertEquals(1, historyRecords.size()); // ESSE ASSERT TÁ FALHANDO
    }
    
    @isTest
    public static void testCreateAsset(){
        // Crie um registro de teste para Account
        Account acc = new Account(Name='Test Account');
        insert acc;

        // Crie um registro de teste para Contact
        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc.Id);
        insert con;

        // Crie um registro de teste para Product2 do tipo Contrato
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true
        //, Frequencia__c = 1, Validade__c = 12, TipoProduto__c = 'Ativo'
        );
        insert prod;

        // Crie um registro de teste para Opportunity com RecordTypeId do tipo Contrato
        Opportunity opp = new Opportunity(Name='Test Opportunity', 
                                          StageName='Needs Analysis', 
                                          CloseDate=Date.today(), 
                                          AccountId=acc.Id, 
                                          ContactId=con.Id, 
                                          RecordTypeId='012as0000001zsfAAA');
        insert opp;
        
        // Altere um campo na Opportunity
         opp.StageName = 'Closed Won';
         update opp; 

        // Crie um registro de teste para OpportunityLineItem
        Pricebook2 stdPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true];
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPricebook.Id, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;
        OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = pbe.Id, Quantity = 1, TotalPrice = 100);
        insert oli;

        // Chame o método handleOpportunities
        OpportunityTriggerHandler.Params params = new OpportunityTriggerHandler.Params();
        params.oppId = opp.Id;
        params.installDate = Date.today();
        List<OpportunityTriggerHandler.Params> paramsList = new List<OpportunityTriggerHandler.Params>{params};
        Test.startTest();
            List<OpportunityTriggerHandler.Result> results = OpportunityTriggerHandler.handleOpportunities(paramsList);
        Test.stopTest();

        // Verifique se um Asset foi criado
        //List<Asset> assets = [SELECT Id FROM Asset WHERE Oportunidade__c = :opp.Id];
        //System.assertEquals(1, assets.size(), 'Expected one Asset to be created');
    }*/

}