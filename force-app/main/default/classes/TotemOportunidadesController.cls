public without sharing class TotemOportunidadesController {
    @AuraEnabled
    public static TotemOportunidadesService.LocalizarCadastroResult localizarCadastro(
        TotemOportunidadesService.LocalizarCadastroRequest req
    ) {
        return TotemOportunidadesService.localizarCadastro(req);
    }

    @AuraEnabled
    public static TotemOportunidadesService.LocalizarCadastroResult localizarCadastroPorValor(
        String searchType,
        String searchValue,
        String cpf,
        Integer codeValidityDays
    ) {
        return TotemOportunidadesService.localizarCadastroPorValor(searchType, searchValue, cpf, codeValidityDays);
    }

    @AuraEnabled
    public static TotemOportunidadesService.AdesaoResult processarAdesao(
        TotemOportunidadesService.AdesaoRequest req
    ) {
        return TotemOportunidadesService.processarAdesao(req);
    }

    @AuraEnabled
    public static TotemOportunidadesService.AdesaoResult processarAdesaoPorValor(
        Id leadId,
        Id opportunityId,
        Boolean allowCreateNew,
        String searchType,
        String searchValue,
        String nomeCompleto,
        String cpf,
        String dataNasc,
        String email,
        String whatsapp,
        String energyRange,
        Boolean hasSolar,
        String tipoLigacao,
        Boolean aceitaTermos,
        Boolean aceitaPoliticaPrivacidade,
        Boolean aceitaContato,
        Decimal monthlyCost,
        String leadSource,
        String leadOrigin,
        String formWeb,
        String partnerCode,
        String campaignCode,
        String pageIdentifier
    ) {
        return TotemOportunidadesService.processarAdesaoPorValor(
            leadId,
            opportunityId,
            allowCreateNew,
            searchType,
            searchValue,
            nomeCompleto,
            cpf,
            dataNasc,
            email,
            whatsapp,
            energyRange,
            hasSolar,
            tipoLigacao,
            aceitaTermos,
            aceitaPoliticaPrivacidade,
            aceitaContato,
            monthlyCost,
            leadSource,
            leadOrigin,
            formWeb,
            partnerCode,
            campaignCode,
            pageIdentifier
        );
    }

    @AuraEnabled
    public static TotemOportunidadesService.AdesaoResult confirmarDadosCliente(
        TotemOportunidadesService.AdesaoRequest req
    ) {
        return TotemOportunidadesService.confirmarDadosCliente(req);
    }

    @AuraEnabled
    public static TotemOportunidadesService.AdesaoResult converterLeadPendente(Id leadId) {
        return TotemOportunidadesService.converterLeadPendente(leadId);
    }

    @AuraEnabled
    public static TotemOportunidadesService.AdesaoResult confirmarDadosClientePorValor(
        Id leadId,
        Id opportunityId,
        Boolean allowCreateNew,
        String searchType,
        String searchValue,
        String nomeCompleto,
        String cpf,
        String dataNasc,
        String email,
        String whatsapp,
        String leadSource,
        String leadOrigin,
        String formWeb,
        String partnerCode,
        String campaignCode,
        String pageIdentifier
    ) {
        return TotemOportunidadesService.confirmarDadosClientePorValor(
            leadId,
            opportunityId,
            allowCreateNew,
            searchType,
            searchValue,
            nomeCompleto,
            cpf,
            dataNasc,
            email,
            whatsapp,
            leadSource,
            leadOrigin,
            formWeb,
            partnerCode,
            campaignCode,
            pageIdentifier
        );
    }

    @AuraEnabled
    public static TotemOportunidadesService.ContaEnergiaResult carregarDadosContaEnergia(
        Id opportunityId,
        Id leadId
    ) {
        return TotemOportunidadesService.carregarDadosContaEnergia(opportunityId, leadId);
    }

    @AuraEnabled
    public static TotemOportunidadesService.ContaEnergiaResult salvarEscolhasContaEnergia(
        Id opportunityId,
        Id leadId,
        Boolean hasSolar,
        String tipoLigacao,
        Decimal monthlyCost,
        String faixaCusto
    ) {
        return TotemOportunidadesService.salvarEscolhasContaEnergia(
            opportunityId,
            leadId,
            hasSolar,
            tipoLigacao,
            monthlyCost,
            faixaCusto
        );
    }

    @AuraEnabled
    public static TotemOportunidadesService.ContaEnergiaResult processarContaEnergia(
        Id opportunityId,
        Id leadId,
        String fileName,
        String base64Data,
        String contentType,
        Boolean hasSolar,
        String tipoLigacao,
        Decimal maxFileSizeMb
    ) {
        return TotemOportunidadesService.processarContaEnergia(
            opportunityId,
            leadId,
            fileName,
            base64Data,
            contentType,
            hasSolar,
            tipoLigacao,
            maxFileSizeMb
        );
    }
}