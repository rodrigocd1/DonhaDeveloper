public without sharing class TotemOportunidadesSelector {
    public static Opportunity getOpportunityEnergy(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> records = [
            SELECT Id, IsClosed, Lead__c, Codigo_no_Parceiro__c, Custo_do_Lead__c, kWh_Medio__c,
                   kWh_Contratado__c, Quanto_Seria__c, Valor_da_Cobranca__c,
                   Economia_Mensal__c, Economia_Anual__c, Distribuidora_Nome__c,
                   Count_Faturas__c, PossuiEnergiaSolar__c, PadraoRede__c,
                   Faixa_de_Custo__c, Distribuidora__c, AccountId, Account.Name, CNPJ__c,
                   Account.Tipo_de_Conta__c, Vertical__c, Vertical_Id__c,
                   Rep_Legal_CPF__c, Rep_Legal__c, Rep_Legal__r.Name,
                   Rep_Legal__r.CPF__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Id getOpportunityLeadId(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> records = [
            SELECT Lead__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0].Lead__c;
    }

    public static Lead getLeadEnergy(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> records = [
            SELECT Id, Custo__c, PossuiEnergiaSolar__c, PadraoRede__c,
                   Faixa_de_Custo__c, Distribuidora__c, Distribuidora_Nome__c,
                   Company, CPF__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Proposta__c getPrimaryProposta(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Proposta__c> propostas = [
            SELECT Id, Oportunidade__c, Numero_do_Cliente__c, Numero_da_Instalacao__c,
                   Titular__c, CPF_CNPJ__c, Distribuidora__c, Distribuidora_Nome__c,
                   Grupo_Tarifario__c, Padrao_da_Rede__c, kWh_Medio__c, Custo_total_R__c,
                   kWh_Contratado__c, Quanto_Seria__c, Economia_Mensal__c,
                   Economia_Anual__c, Pct_Desconto_Verde__c, Tipo_de_Conta__c,
                   Vertical__c, Vertical_Id__c, Tarifa_Kwh_com_impostos_R__c,
                   Iluminacao_Publica_R__c, Consumo_Total_KWh__c, Deducoes__c,
                   Custo_total_com_deducoes__c, Boleto_Distribuidora_R__c,
                   Boleto_Gerador_Parceiro_R__c, Compensavel_KWh__c,
                   Minimo_Distribuidora_KWh__c, Tarifa_com_desconto_R__c,
                   Total_2_boletos__c, Economia_Mensal_Simulador__c
            FROM Proposta__c
            WHERE Oportunidade__c = :opportunityId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return propostas.isEmpty() ? null : propostas[0];
    }

    public static List<Lead> getLeadsByCodes(Set<String> codeCandidates, Integer limitSize) {
        if (codeCandidates == null || codeCandidates.isEmpty()) {
            return new List<Lead>();
        }
        Integer queryLimit = limitSize == null ? 20 : limitSize;
        return [
            SELECT Id, FirstName, LastName, Company, Email, MobilePhone, CPF__c,
                   Data_de_Nascimento__c, IsConverted, ConvertedOpportunityId,
                   CreatedDate, Codigo_no_Parceiro__c, Custo__c
            FROM Lead
            WHERE Codigo_no_Parceiro__c IN :codeCandidates
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Lead> getLeadsByPhoneLike(String likePattern, Integer limitSize) {
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, FirstName, LastName, Company, Email, MobilePhone, CPF__c,
                   Data_de_Nascimento__c, IsConverted, ConvertedOpportunityId,
                   CreatedDate, Codigo_no_Parceiro__c, Custo__c
            FROM Lead
            WHERE MobilePhone LIKE :likePattern
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Contact> getContactsByPhoneLike(String likePattern, Integer limitSize) {
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, FirstName, LastName, Name, Email, MobilePhone, CPF__c, Data_de_Nascimento__c
            FROM Contact
            WHERE MobilePhone LIKE :likePattern
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Lead> getLeadsByEmail(String email, Integer limitSize) {
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, FirstName, LastName, Company, Email, MobilePhone, CPF__c,
                   Data_de_Nascimento__c, IsConverted, ConvertedOpportunityId,
                   CreatedDate, Codigo_no_Parceiro__c, Custo__c
            FROM Lead
            WHERE Email = :email
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Contact> getContactsByEmail(String email, Integer limitSize) {
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, FirstName, LastName, Name, Email, MobilePhone, CPF__c, Data_de_Nascimento__c
            FROM Contact
            WHERE Email = :email
            ORDER BY LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Opportunity> getOpportunitiesByLeadIdsOrIds(
        Set<Id> opportunityIds,
        Set<Id> leadIds,
        Integer limitSize
    ) {
        if ((opportunityIds == null || opportunityIds.isEmpty()) && (leadIds == null || leadIds.isEmpty())) {
            return new List<Opportunity>();
        }
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, Name, IsClosed, IsWon, StageName, Lead__c, Rep_Legal__c,
                   Rep_Legal__r.FirstName, Rep_Legal__r.LastName, Rep_Legal__r.Name,
                   Rep_Legal__r.Email, Rep_Legal__r.MobilePhone, Rep_Legal__r.CPF__c,
                   Rep_Legal__r.Data_de_Nascimento__c, Custo_do_Lead__c
            FROM Opportunity
            WHERE Id IN :opportunityIds OR Lead__c IN :leadIds
            ORDER BY IsClosed ASC, LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static List<Opportunity> getOpportunitiesByContactIds(Set<Id> contactIds, Integer limitSize) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Opportunity>();
        }
        Integer queryLimit = limitSize == null ? 50 : limitSize;
        return [
            SELECT Id, Name, IsClosed, IsWon, StageName, Lead__c, Rep_Legal__c,
                   Rep_Legal__r.FirstName, Rep_Legal__r.LastName, Rep_Legal__r.Name,
                   Rep_Legal__r.Email, Rep_Legal__r.MobilePhone, Rep_Legal__r.CPF__c,
                   Rep_Legal__r.Data_de_Nascimento__c, Custo_do_Lead__c
            FROM Opportunity
            WHERE Rep_Legal__c IN :contactIds
            ORDER BY IsClosed ASC, LastModifiedDate DESC
            LIMIT :queryLimit
        ];
    }

    public static Opportunity getOpportunityForCustomer(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> records = [
            SELECT Id, Name, IsClosed, Lead__c, Codigo_no_Parceiro__c, Rep_Legal__c,
                   Rep_Legal__r.FirstName, Rep_Legal__r.LastName, Rep_Legal__r.Email,
                   Rep_Legal__r.MobilePhone, Rep_Legal__r.CPF__c, Rep_Legal__r.Data_de_Nascimento__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Lead getLeadForCustomer(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> records = [
            SELECT Id, FirstName, LastName, Company, Email, MobilePhone, CPF__c,
                   Data_de_Nascimento__c, IsConverted, ConvertedOpportunityId,
                   Codigo_no_Parceiro__c, Custo__c, PossuiEnergiaSolar__c,
                   PadraoRede__c, Faixa_de_Custo__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Opportunity getOpportunityCandidate(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> records = [
            SELECT Id, Name, IsClosed, IsWon, StageName, Lead__c, Codigo_no_Parceiro__c, Rep_Legal__c,
                   Rep_Legal__r.FirstName, Rep_Legal__r.LastName, Rep_Legal__r.Name,
                   Rep_Legal__r.Email, Rep_Legal__r.MobilePhone, Rep_Legal__r.CPF__c,
                   Rep_Legal__r.Data_de_Nascimento__c, Custo_do_Lead__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Lead getLeadCandidate(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> records = [
            SELECT Id, FirstName, LastName, Company, Email, MobilePhone, CPF__c,
                   Data_de_Nascimento__c, IsConverted, ConvertedOpportunityId,
                   CreatedDate, Codigo_no_Parceiro__c, Custo__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static String getConvertedLeadStatus() {
        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];
        return statuses.isEmpty() ? null : statuses[0].MasterLabel;
    }

    public static Lead getLeadEnergyForCopy(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> records = [
            SELECT Id, Codigo_no_Parceiro__c, PossuiEnergiaSolar__c, PadraoRede__c, Faixa_de_Custo__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Lead getLeadCode(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> records = [
            SELECT Id, Codigo_no_Parceiro__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Opportunity getOpportunityCode(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> records = [
            SELECT Id, Codigo_no_Parceiro__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

}