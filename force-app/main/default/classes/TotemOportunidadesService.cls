public without sharing class TotemOportunidadesService {

    private static final String SEARCH_CODIGO = 'CODIGO';
    private static final String SEARCH_WHATSAPP = 'WHATSAPP';
    private static final String SEARCH_EMAIL = 'EMAIL';
    private static final Integer DEFAULT_CODE_VALIDITY_DAYS = 30;
    private static final Integer MAX_SEARCH_RESULTS = 50;
    private static final Decimal DEFAULT_MAX_BILL_FILE_SIZE_MB = 4;
    private static final Decimal SERVER_MAX_BILL_FILE_SIZE_MB = 6;
    private static final Decimal VEO_SIMULATION_DISCOUNT_PERCENT = 15;
    private static final Decimal VEO_SIMULATION_TARIFF_WITH_TAXES = 1.05;
    private static final Decimal VEO_SIMULATION_PUBLIC_LIGHTING = 15;
    private static final Decimal VEO_SIMULATION_DEFAULT_DEDUCTIONS = 0;
    private static final String BILL_NOT_RECOGNIZED_MESSAGE = 'Não conseguimos identificar todas as informações da conta. Tire uma nova foto ou envie outro arquivo.';
    private static final String BILL_SERVICE_UNAVAILABLE_MESSAGE = 'Não foi possível analisar a conta neste momento. Tente novamente em alguns instantes.';

    public class LocalizarCadastroRequest {
        @AuraEnabled public String searchType;
        @AuraEnabled public String searchValue;
        @AuraEnabled public String cpf;
        @AuraEnabled public Integer codeValidityDays;
    }

    public class CadastroMatch {
        @AuraEnabled public String key;
        @AuraEnabled public String recordType;
        @AuraEnabled public String maskedName;
        @AuraEnabled public String maskedEmail;
        @AuraEnabled public String maskedWhatsapp;
    }

    public class LocalizarCadastroResult {
        @AuraEnabled public String status;
        @AuraEnabled public String mensagem;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Boolean validatedByCode;
        @AuraEnabled public Boolean canCreateNew;
        @AuraEnabled public Integer nextStep;
        @AuraEnabled public String nomeCompleto;
        @AuraEnabled public String cpf;
        @AuraEnabled public String dataNasc;
        @AuraEnabled public String whatsapp;
        @AuraEnabled public String email;
        @AuraEnabled public List<CadastroMatch> matches;
    }

    public class AdesaoRequest {
        @AuraEnabled public Id      leadId;
        @AuraEnabled public Id      opportunityId;
        @AuraEnabled public Boolean allowCreateNew;
        @AuraEnabled public String  searchType;
        @AuraEnabled public String  searchValue;
        @AuraEnabled public String  nomeCompleto;
        @AuraEnabled public String  cpf;
        @AuraEnabled public String  dataNasc;
        @AuraEnabled public String  email;
        @AuraEnabled public String  whatsapp;
        @AuraEnabled public String  energyRange;
        @AuraEnabled public Boolean hasSolar;
        @AuraEnabled public String  tipoLigacao;
        @AuraEnabled public Boolean aceitaTermos;
        @AuraEnabled public Boolean aceitaPoliticaPrivacidade;
        @AuraEnabled public Boolean aceitaContato;
        @AuraEnabled public Decimal monthlyCost;
        @AuraEnabled public String  leadSource;
        @AuraEnabled public String  leadOrigin;
        @AuraEnabled public String  formWeb;
        @AuraEnabled public String  partnerCode;
        @AuraEnabled public String  campaignCode;
        @AuraEnabled public String  pageIdentifier;
    }

    public class AdesaoResult {
        @AuraEnabled public Id      leadId;
        @AuraEnabled public Id      opportunityId;
        @AuraEnabled public String  codigoUnico;
        @AuraEnabled public Boolean sucesso;
        @AuraEnabled public Boolean leadCriado;
        @AuraEnabled public Boolean conversaoPendente;
        @AuraEnabled public String  erroConversao;
        @AuraEnabled public String  mensagem;
    }

    public class ContaEnergiaResult {
        @AuraEnabled public String status;
        @AuraEnabled public String mensagem;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id propostaId;
        @AuraEnabled public Id documentoId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Boolean hasSolar;
        @AuraEnabled public String tipoLigacao;
        @AuraEnabled public String tipoLigacaoLabel;
        @AuraEnabled public Boolean hasRequiredEnergyData;
        @AuraEnabled public Boolean hasRecognizedBillData;
        @AuraEnabled public Boolean hasManualEstimate;
        @AuraEnabled public Boolean hasSimulationData;
        @AuraEnabled public Boolean elegivel;
        @AuraEnabled public String simulationMessage;
        @AuraEnabled public String renewableInfo;
        @AuraEnabled public String faixaCusto;
        @AuraEnabled public Decimal monthlyCost;
        @AuraEnabled public Decimal contaEstimada;
        @AuraEnabled public Decimal economiaMensal;
        @AuraEnabled public Decimal economiaAnual;
        @AuraEnabled public Decimal descontoPercent;
        @AuraEnabled public Decimal descontoPorKwh;
        @AuraEnabled public Decimal disponibilidadeKwh;
        @AuraEnabled public Decimal tarifaKwhComImpostos;
        @AuraEnabled public Decimal iluminacaoPublica;
        @AuraEnabled public Decimal consumoTotalKwh;
        @AuraEnabled public Decimal tarifaComDesconto;
        @AuraEnabled public Decimal boletoDistribuidora;
        @AuraEnabled public Decimal boletoGeradorParceiro;
        @AuraEnabled public Decimal totalDoisBoletos;
        @AuraEnabled public Decimal deducoes;
        @AuraEnabled public Decimal custoTotalComDeducoes;
        @AuraEnabled public Decimal kwhMedio;
        @AuraEnabled public Decimal kwhContratado;
        @AuraEnabled public Decimal countFaturas;
        @AuraEnabled public String numeroCliente;
        @AuraEnabled public String numeroInstalacao;
    }

    private class EnergyContext {
        public Id opportunityId;
        public Id leadId;
        public Opportunity opportunity;
        public Lead lead;
        public Proposta__c proposta;
    }

    private class CadastroCandidate {
        public String recordType;
        public Lead lead;
        public Opportunity opportunity;

        public CadastroCandidate(Lead lead) {
            this.recordType = 'LEAD';
            this.lead = lead;
        }

        public CadastroCandidate(Opportunity opportunity) {
            this.recordType = 'OPPORTUNITY';
            this.opportunity = opportunity;
        }

        public Boolean isOpenOpportunity() {
            return opportunity != null && opportunity.IsClosed == false;
        }

        public Boolean isClosedOpportunity() {
            return opportunity != null && opportunity.IsClosed == true;
        }

        public Boolean isUnconvertedLead() {
            return lead != null && lead.IsConverted == false;
        }

        public Integer priority() {
            if (isOpenOpportunity()) {
                return 1;
            }
            if (isUnconvertedLead()) {
                return 2;
            }
            if (isClosedOpportunity()) {
                return 3;
            }
            return 9;
        }

        public Id recordId() {
            return opportunity != null ? opportunity.Id : lead.Id;
        }

        public String nomeCompleto() {
            if (opportunity != null && opportunity.Rep_Legal__r != null) {
                return opportunity.Rep_Legal__r.Name;
            }
            if (lead != null) {
                if (!String.isBlank(lead.FirstName) || !String.isBlank(lead.LastName)) {
                    return String.join(new List<String>{ lead.FirstName, lead.LastName }, ' ').trim();
                }
                return lead.Company;
            }
            return null;
        }

        public String cpf() {
            if (opportunity != null && opportunity.Rep_Legal__r != null) {
                return opportunity.Rep_Legal__r.CPF__c;
            }
            return lead != null ? lead.CPF__c : null;
        }

        public Date dataNasc() {
            if (opportunity != null && opportunity.Rep_Legal__r != null) {
                return opportunity.Rep_Legal__r.Data_de_Nascimento__c;
            }
            return lead != null ? lead.Data_de_Nascimento__c : null;
        }

        public String whatsapp() {
            if (opportunity != null && opportunity.Rep_Legal__r != null) {
                return opportunity.Rep_Legal__r.MobilePhone;
            }
            return lead != null ? lead.MobilePhone : null;
        }

        public String email() {
            if (opportunity != null && opportunity.Rep_Legal__r != null) {
                return opportunity.Rep_Legal__r.Email;
            }
            return lead != null ? lead.Email : null;
        }
    }

    @AuraEnabled
    public static LocalizarCadastroResult localizarCadastro(LocalizarCadastroRequest req) {
        LocalizarCadastroResult result = new LocalizarCadastroResult();
        result.matches = new List<CadastroMatch>();
        result.nextStep = 1;
        result.canCreateNew = false;
        result.validatedByCode = false;

        if (req == null || String.isBlank(req.searchType) || String.isBlank(req.searchValue)) {
            result.status = 'INVALID_INPUT';
            result.mensagem = 'Informe um criterio de busca.';
            return result;
        }

        String searchType = req.searchType.trim().toUpperCase();
        if (searchType == SEARCH_CODIGO) {
            return localizarPorCodigo(req);
        }
        if (searchType == SEARCH_WHATSAPP) {
            return localizarPorWhatsapp(req);
        }
        if (searchType == SEARCH_EMAIL) {
            return localizarPorEmail(req);
        }

        result.status = 'INVALID_INPUT';
        result.mensagem = 'Criterio de busca invalido.';
        return result;
    }

    @AuraEnabled
    public static LocalizarCadastroResult localizarCadastroPorValor(
        String searchType,
        String searchValue,
        String cpf,
        Integer codeValidityDays
    ) {
        LocalizarCadastroRequest req = new LocalizarCadastroRequest();
        req.searchType = searchType;
        req.searchValue = searchValue;
        req.cpf = cpf;
        req.codeValidityDays = codeValidityDays;
        return localizarCadastro(req);
    }

    @AuraEnabled
    public static AdesaoResult processarAdesao(AdesaoRequest req) {
        hydrateAdesaoRequest(req);
        validateAdesao(req);
        return finalizarAdesaoOportunidade(req);
    }

    @AuraEnabled
    public static AdesaoResult processarAdesaoPorValor(
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
        AdesaoRequest req = new AdesaoRequest();
        req.leadId = leadId;
        req.opportunityId = opportunityId;
        req.allowCreateNew = allowCreateNew;
        req.searchType = searchType;
        req.searchValue = searchValue;
        req.nomeCompleto = nomeCompleto;
        req.cpf = cpf;
        req.dataNasc = dataNasc;
        req.email = email;
        req.whatsapp = whatsapp;
        req.energyRange = energyRange;
        req.hasSolar = hasSolar;
        req.tipoLigacao = tipoLigacao;
        req.aceitaTermos = aceitaTermos;
        req.aceitaPoliticaPrivacidade = aceitaPoliticaPrivacidade;
        req.aceitaContato = aceitaContato;
        req.monthlyCost = monthlyCost;
        req.leadSource = leadSource;
        req.leadOrigin = leadOrigin;
        req.formWeb = formWeb;
        req.partnerCode = partnerCode;
        req.campaignCode = campaignCode;
        req.pageIdentifier = pageIdentifier;
        return processarAdesao(req);
    }

    @AuraEnabled
    public static AdesaoResult confirmarDadosCliente(AdesaoRequest req) {
        validateDadosCliente(req);
        AdesaoResult result = resolverCadastroCliente(req, 'confirmarDadosCliente');
        if (result.leadCriado == true) {
            return result;
        }
        if (result.opportunityId == null && result.conversaoPendente == true) {
            return result;
        }
        if (result.opportunityId == null) {
            throw new AuraHandledException(conversionFailureMessage(result));
        }
        return result;
    }

    @AuraEnabled
    public static AdesaoResult converterLeadPendente(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead nao informado para conversao.');
        }

        Lead lead = TotemOportunidadesSelector.getLeadForCustomer(leadId);
        if (lead == null) {
            throw new AuraHandledException('Lead nao encontrado para conversao.');
        }

        AdesaoResult result = new AdesaoResult();
        result.leadId = lead.Id;
        result.codigoUnico = ensureLeadCode(lead);

        if (lead.ConvertedOpportunityId != null) {
            result.sucesso = true;
            result.opportunityId = lead.ConvertedOpportunityId;
            result.mensagem = 'Lead ja convertido.';
            linkOpportunityToLead(result.opportunityId, lead.Id);
            return result;
        }

        converterLead(lead.Id, result);
        if (result.opportunityId == null && result.conversaoPendente != true) {
            throw new AuraHandledException(conversionFailureMessage(result));
        }
        return result;
    }

    @AuraEnabled
    public static AdesaoResult confirmarDadosClientePorValor(
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
        AdesaoRequest req = new AdesaoRequest();
        req.leadId = leadId;
        req.opportunityId = opportunityId;
        req.allowCreateNew = allowCreateNew;
        req.searchType = searchType;
        req.searchValue = searchValue;
        req.nomeCompleto = nomeCompleto;
        req.cpf = cpf;
        req.dataNasc = dataNasc;
        req.email = email;
        req.whatsapp = whatsapp;
        req.leadSource = leadSource;
        req.leadOrigin = leadOrigin;
        req.formWeb = formWeb;
        req.partnerCode = partnerCode;
        req.campaignCode = campaignCode;
        req.pageIdentifier = pageIdentifier;
        return confirmarDadosCliente(req);
    }

    @AuraEnabled
    public static ContaEnergiaResult carregarDadosContaEnergia(Id opportunityId, Id leadId) {
        EnergyContext context = resolveEnergyContext(opportunityId, leadId, false, null);
        return buildContaEnergiaResult(context.opportunity, context.lead, context.proposta);
    }

    @AuraEnabled
    public static ContaEnergiaResult salvarEscolhasContaEnergia(
        Id opportunityId,
        Id leadId,
        Boolean hasSolar,
        String tipoLigacao,
        Decimal monthlyCost,
        String faixaCusto
    ) {
        try {
            EnergyContext context = resolveEnergyContext(opportunityId, leadId, true, tipoLigacao);
            if (context.opportunity == null || context.opportunity.IsClosed) {
                return contaEnergiaError('INVALID_CONTEXT', 'Não foi possível preparar a oportunidade para receber os dados da conta.');
            }
            if (context.proposta == null) {
                return contaEnergiaError('SERVICE_UNAVAILABLE', 'Não foi possível preparar a proposta para receber a conta. Tente novamente em alguns instantes.');
            }

            Decimal normalizedMonthlyCost = positive(monthlyCost) ? monthlyCost : monthlyCostFromFaixaCusto(faixaCusto);
            persistEnergyChoices(
                context.opportunityId,
                context.leadId,
                context.proposta.Id,
                hasSolar,
                tipoLigacao,
                false,
                normalizedMonthlyCost,
                faixaCusto
            );
            ContaEnergiaResult result = carregarDadosContaEnergia(context.opportunityId, context.leadId);
            if (positive(normalizedMonthlyCost)) {
                result.monthlyCost = normalizedMonthlyCost;
                result.contaEstimada = normalizedMonthlyCost;
                applySimulationData(result);
                result.hasManualEstimate = true;
                result.hasSimulationData = positive(result.contaEstimada) &&
                    result.economiaMensal != null &&
                    result.economiaAnual != null &&
                    result.descontoPercent != null &&
                    result.economiaMensal > 0;
            }
            persistSimulationFields(result);
            return result;
        } catch (Exception ex) {
            safeLog('salvarEscolhasContaEnergia', 'Falha ao salvar dados da conta. ' + ex.getMessage());
            return contaEnergiaError('SERVICE_UNAVAILABLE', 'Não foi possível salvar os dados da conta. Tente novamente.');
        }
    }

    @AuraEnabled
    public static ContaEnergiaResult processarContaEnergia(
        Id opportunityId,
        Id leadId,
        String fileName,
        String base64Data,
        String contentType,
        Boolean hasSolar,
        String tipoLigacao,
        Decimal maxFileSizeMb
    ) {
        EnergyContext context = resolveEnergyContext(opportunityId, leadId, true, tipoLigacao);
        ContaEnergiaResult invalidResult = validateBillInput(context.opportunityId, fileName, base64Data, contentType, maxFileSizeMb);
        if (invalidResult != null) {
            return invalidResult;
        }

        Opportunity opp = context.opportunity;
        if (opp == null || opp.IsClosed) {
            return contaEnergiaError('INVALID_CONTEXT', 'Não foi possível preparar a oportunidade para receber a conta.');
        }

        Proposta__c proposta = context.proposta;
        if (proposta == null) {
            return contaEnergiaError('SERVICE_UNAVAILABLE', 'Não foi possível preparar a proposta para receber a conta. Tente novamente em alguns instantes.');
        }

        String normalizedFileName = sanitizeFileName(fileName);
        String extension = extensionFromFileName(normalizedFileName);
        String fileUrl;
        Proposta_OCR_Fatura_V2.infoOCR ocr;

        try {
            fileUrl = FileUploaderService.uploadFile(normalizedFileName, cleanBase64(base64Data));
            ocr = Proposta_OCR_Fatura_V2.ler_fatura(fileUrl, proposta.Distribuidora_Nome__c);
        } catch (Exception ex) {
            safeLog('processarContaEnergia', 'Servico de upload/OCR indisponivel para a conta de energia.');
            return contaEnergiaError('SERVICE_UNAVAILABLE', BILL_SERVICE_UNAVAILABLE_MESSAGE);
        }

        Boolean hasServiceError = ocr == null || !String.isBlank(ocr.errorMessage);
        Boolean recognized = !hasServiceError && hasRequiredOcrData(ocr);
        String documentMessage = recognized
            ? null
            : (hasServiceError ? BILL_SERVICE_UNAVAILABLE_MESSAGE : BILL_NOT_RECOGNIZED_MESSAGE);

        Documento_da_Proposta__c doc = new Documento_da_Proposta__c(
            Proposta__c = proposta.Id,
            Oportunidade__c = context.opportunityId,
            Nome__c = normalizedFileName,
            Tipo__c = 'Fatura',
            Extensao_do_Arquivo__c = extension,
            Link__c = fileUrl,
            Leitura_OCR__c = recognized,
            Mensagem_de_erro__c = documentMessage
        );
        Database.SaveResult docResult = Database.insert(doc, false);
        if (!docResult.isSuccess()) {
            safeLog('processarContaEnergia', 'Nao foi possivel criar Documento_da_Proposta__c para a fatura do totem.');
            return contaEnergiaError('SERVICE_UNAVAILABLE', BILL_SERVICE_UNAVAILABLE_MESSAGE);
        }

        if (hasServiceError) {
            ContaEnergiaResult result = contaEnergiaError('SERVICE_UNAVAILABLE', BILL_SERVICE_UNAVAILABLE_MESSAGE);
            result.documentoId = doc.Id;
            return result;
        }

        if (!recognized) {
            ContaEnergiaResult result = contaEnergiaError('NOT_RECOGNIZED', BILL_NOT_RECOGNIZED_MESSAGE);
            result.documentoId = doc.Id;
            return result;
        }

        Database.SaveResult propostaResult = Database.update(buildPropostaFromOcr(proposta.Id, ocr, tipoLigacao), false);
        if (!propostaResult.isSuccess()) {
            update new Documento_da_Proposta__c(
                Id = doc.Id,
                Leitura_OCR__c = false,
                Mensagem_de_erro__c = BILL_NOT_RECOGNIZED_MESSAGE
            );
            safeLog('processarContaEnergia', 'OCR retornou dados, mas a proposta nao aceitou a atualizacao.');
            ContaEnergiaResult result = contaEnergiaError('NOT_RECOGNIZED', BILL_NOT_RECOGNIZED_MESSAGE);
            result.documentoId = doc.Id;
            return result;
        }

        persistEnergyChoices(context.opportunityId, context.leadId, proposta.Id, hasSolar, tipoLigacao, true, null, null);

        ContaEnergiaResult result = carregarDadosContaEnergia(context.opportunityId, context.leadId);
        persistSimulationFields(result);
        result.status = 'OK';
        result.mensagem = 'Conta analisada com sucesso.';
        result.documentoId = doc.Id;
        result.fileName = normalizedFileName;
        return result;
    }

    private static ContaEnergiaResult validateBillInput(
        Id opportunityId,
        String fileName,
        String base64Data,
        String contentType,
        Decimal maxFileSizeMb
    ) {
        if (opportunityId == null) {
            return contaEnergiaError('INVALID_CONTEXT', 'Localize e confirme o cliente antes de enviar a conta.');
        }
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            return contaEnergiaError('INVALID_FILE', 'Envie ou fotografe a conta de energia para continuar.');
        }

        String extension = extensionFromFileName(fileName);
        Set<String> allowedExtensions = new Set<String>{ 'pdf', 'jpg', 'jpeg', 'png' };
        if (String.isBlank(extension) || !allowedExtensions.contains(extension)) {
            return contaEnergiaError('INVALID_FILE', 'Formato não suportado. Envie PDF, JPG, JPEG ou PNG.');
        }

        Decimal normalizedMaxMb = maxFileSizeMb == null || maxFileSizeMb <= 0
            ? DEFAULT_MAX_BILL_FILE_SIZE_MB
            : maxFileSizeMb;
        if (normalizedMaxMb > SERVER_MAX_BILL_FILE_SIZE_MB) {
            normalizedMaxMb = SERVER_MAX_BILL_FILE_SIZE_MB;
        }
        Integer estimatedBytes = estimateBase64Bytes(base64Data);
        if (estimatedBytes > normalizedMaxMb * 1024 * 1024) {
            return contaEnergiaError('INVALID_FILE', 'Arquivo acima do tamanho permitido para envio.');
        }
        return null;
    }

    private static ContaEnergiaResult buildContaEnergiaResult(
        Opportunity opp,
        Lead lead,
        Proposta__c proposta
    ) {
        ContaEnergiaResult result = new ContaEnergiaResult();
        result.status = 'OK';
        result.mensagem = 'Dados de energia carregados.';
        result.opportunityId = opp == null ? null : opp.Id;
        result.leadId = lead == null ? (opp == null ? null : opp.Lead__c) : lead.Id;
        result.propostaId = proposta == null ? null : proposta.Id;
        result.hasSolar = opp != null ? opp.PossuiEnergiaSolar__c : (lead == null ? null : lead.PossuiEnergiaSolar__c);
        result.faixaCusto = firstString(
            opp == null ? null : opp.Faixa_de_Custo__c,
            lead == null ? null : lead.Faixa_de_Custo__c
        );

        String padraoRede = firstString(
            proposta == null ? null : proposta.Padrao_da_Rede__c,
            firstString(
                opp == null ? null : opp.PadraoRede__c,
                lead == null ? null : lead.PadraoRede__c
            )
        );
        result.tipoLigacaoLabel = padraoRede;
        result.tipoLigacao = ligacaoKeyFromPadrao(padraoRede);

        result.numeroCliente = proposta == null ? null : proposta.Numero_do_Cliente__c;
        result.numeroInstalacao = proposta == null ? null : proposta.Numero_da_Instalacao__c;
        result.kwhMedio = firstDecimal(new List<Object>{
            opp == null ? null : opp.kWh_Medio__c,
            proposta == null ? null : proposta.kWh_Medio__c
        });
        result.kwhContratado = opp == null ? null : opp.kWh_Contratado__c;
        result.countFaturas = opp == null ? null : opp.Count_Faturas__c;

        Decimal faixaMonthlyCost = monthlyCostFromFaixaCusto(result.faixaCusto);
        result.monthlyCost = firstDecimal(new List<Object>{
            faixaMonthlyCost,
            proposta == null ? null : proposta.Custo_total_R__c,
            opp == null ? null : opp.Valor_da_Cobranca__c,
            opp == null ? null : opp.Custo_do_Lead__c,
            opp == null ? null : opp.Quanto_Seria__c,
            lead == null ? null : lead.Custo__c
        });
        result.contaEstimada = firstDecimal(new List<Object>{
            faixaMonthlyCost,
            result.monthlyCost,
            proposta == null ? null : proposta.Custo_total_R__c,
            opp == null ? null : opp.Valor_da_Cobranca__c,
            opp == null ? null : opp.Quanto_Seria__c,
            opp == null ? null : opp.Custo_do_Lead__c
        });

        applySimulationData(result);

        result.hasRecognizedBillData = proposta != null &&
            (!String.isBlank(proposta.Numero_da_Instalacao__c) || positive(result.kwhMedio));
        result.hasManualEstimate = !result.hasRecognizedBillData && positive(result.monthlyCost);
        result.hasRequiredEnergyData = result.hasRecognizedBillData;
        result.hasSimulationData = positive(result.contaEstimada) &&
            result.economiaMensal != null &&
            result.economiaAnual != null &&
            result.descontoPercent != null &&
            result.economiaMensal > 0;
        return result;
    }

    private static void applySimulationData(ContaEnergiaResult result) {
        result.renewableInfo = buildRenewableInfo();
        result.descontoPercent = VEO_SIMULATION_DISCOUNT_PERCENT;
        result.tarifaKwhComImpostos = VEO_SIMULATION_TARIFF_WITH_TAXES;
        result.iluminacaoPublica = VEO_SIMULATION_PUBLIC_LIGHTING;
        result.deducoes = VEO_SIMULATION_DEFAULT_DEDUCTIONS;
        result.disponibilidadeKwh = availabilityKwh(result.tipoLigacaoLabel);

        result.consumoTotalKwh = calculateTotalConsumptionKwh(
            result.contaEstimada,
            result.iluminacaoPublica,
            result.tarifaKwhComImpostos
        );
        result.kwhContratado = calculateContractedKwh(result.consumoTotalKwh, result.disponibilidadeKwh);
        result.descontoPorKwh = calculateEstimatedDiscountPerKwh(result.tarifaKwhComImpostos, result.descontoPercent);
        result.tarifaComDesconto = calculateDiscountedTariff(result.tarifaKwhComImpostos, result.descontoPercent);
        result.boletoDistribuidora = calculateUtilityBill(
            result.disponibilidadeKwh,
            result.tarifaKwhComImpostos,
            result.iluminacaoPublica
        );
        result.boletoGeradorParceiro = calculatePartnerGeneratorBill(result.kwhContratado, result.tarifaComDesconto);
        result.totalDoisBoletos = calculateTotalBills(result.boletoDistribuidora, result.boletoGeradorParceiro);
        result.custoTotalComDeducoes = calculateBillMinusDeductions(result.contaEstimada, result.deducoes);
        result.economiaMensal = calculateFlowSimulationSavings(result.custoTotalComDeducoes, result.totalDoisBoletos);
        result.economiaAnual = result.economiaMensal == null ? null : (result.economiaMensal * 12).setScale(2);
        result.elegivel = positive(result.economiaMensal);
        result.simulationMessage = buildSimulationMessage(result);
        logSimulationInputs(result);
    }

    private static void logSimulationInputs(ContaEnergiaResult result) {
        if (result == null) {
            return;
        }

        System.debug(LoggingLevel.INFO, '[TotemOportunidadesFluxo] Entradas da simulação: ' + new Map<String, Object>{
            'custoTotalUtilizado' => result.contaEstimada,
            'monthlyCost' => result.monthlyCost,
            'descontoPercentual' => result.descontoPercent,
            'tarifaKwhComImpostos' => result.tarifaKwhComImpostos,
            'iluminacaoPublica' => result.iluminacaoPublica,
            'padraoRede' => result.tipoLigacaoLabel,
            'disponibilidadeKwh' => result.disponibilidadeKwh,
            'consumoTotalKwh' => result.consumoTotalKwh,
            'compensavelKwh' => result.kwhContratado,
            'deducoes' => result.deducoes,
            'custoTotalComDeducoes' => result.custoTotalComDeducoes,
            'tarifaComDesconto' => result.tarifaComDesconto,
            'boletoDistribuidora' => result.boletoDistribuidora,
            'boletoGeradorParceiro' => result.boletoGeradorParceiro,
            'totalDoisBoletos' => result.totalDoisBoletos,
            'economiaMensal' => result.economiaMensal,
            'economiaAnual' => result.economiaAnual
        });
    }

    private static Decimal availabilityKwh(String padraoRede) {
        String key = ligacaoKeyFromPadrao(padraoRede);
        if (key == 'mono') {
            return 30;
        }
        if (key == 'bi') {
            return 50;
        }
        if (key == 'tri') {
            return 100;
        }
        return 0;
    }

    private static Decimal calculateContractedKwh(Decimal consumptionKwh, Decimal availabilityKwh) {
        if (!positive(consumptionKwh)) {
            return null;
        }
        Decimal contracted = consumptionKwh - (availabilityKwh == null ? 0 : availabilityKwh);
        return contracted > 0 ? contracted.setScale(0, RoundingMode.HALF_UP) : null;
    }

    private static Decimal calculateTotalConsumptionKwh(
        Decimal totalBill,
        Decimal publicLighting,
        Decimal tariffWithTaxes
    ) {
        if (!positive(totalBill) || !positive(tariffWithTaxes)) {
            return null;
        }
        Decimal billWithoutPublicLighting = totalBill - (publicLighting == null ? 0 : publicLighting);
        if (billWithoutPublicLighting <= 0) {
            return null;
        }
        return (billWithoutPublicLighting / tariffWithTaxes).setScale(0, RoundingMode.HALF_UP);
    }

    private static Decimal calculateEstimatedDiscountPerKwh(Decimal tariffWithTaxes, Decimal discountPercent) {
        if (!positive(tariffWithTaxes) || !positive(discountPercent)) {
            return null;
        }
        return (tariffWithTaxes * discountPercent / 100).setScale(6);
    }

    private static Decimal calculateDiscountedTariff(Decimal tariffWithTaxes, Decimal discountPercent) {
        if (!positive(tariffWithTaxes) || !positive(discountPercent)) {
            return null;
        }
        return (tariffWithTaxes - (tariffWithTaxes * discountPercent / 100)).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal calculateUtilityBill(
        Decimal availabilityKwh,
        Decimal tariffWithTaxes,
        Decimal publicLighting
    ) {
        if (!positive(tariffWithTaxes)) {
            return null;
        }
        Decimal utilityKwh = availabilityKwh == null ? 0 : availabilityKwh;
        Decimal lighting = publicLighting == null ? 0 : publicLighting;
        return ((utilityKwh * tariffWithTaxes) + lighting).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal calculatePartnerGeneratorBill(Decimal contractedKwh, Decimal discountedTariff) {
        if (!positive(contractedKwh) || !positive(discountedTariff)) {
            return null;
        }
        return (contractedKwh * discountedTariff).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal calculateTotalBills(Decimal utilityBill, Decimal partnerGeneratorBill) {
        if (utilityBill == null || partnerGeneratorBill == null) {
            return null;
        }
        return (utilityBill + partnerGeneratorBill).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal calculateBillMinusDeductions(Decimal totalBill, Decimal deductions) {
        if (!positive(totalBill)) {
            return null;
        }
        return (totalBill - (deductions == null ? 0 : deductions)).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal calculateFlowSimulationSavings(Decimal billMinusDeductions, Decimal totalBills) {
        if (billMinusDeductions == null || totalBills == null) {
            return null;
        }
        return (billMinusDeductions - totalBills).setScale(2, RoundingMode.HALF_UP);
    }

    private static Decimal monthlyCostFromFaixaCusto(String faixaCusto) {
        if (String.isBlank(faixaCusto)) {
            return null;
        }

        String normalized = faixaCusto.trim().toLowerCase();
        if (normalized.contains('1.000') || normalized.contains('1000') || normalized.contains('acima')) {
            return 850;
        }
        if (normalized.contains('500') && normalized.contains('700')) {
            return 600;
        }
        if (normalized.contains('200') && (normalized.contains('500') || normalized.contains('400'))) {
            return 350;
        }
        if (normalized.contains('200') && (normalized.contains('menor') || normalized.contains('até') || normalized.contains('ate'))) {
            return 200;
        }
        return null;
    }

    private static String buildRenewableInfo() {
        return 'Energia renovável com créditos compensados pela VEO.';
    }

    private static String buildSimulationMessage(ContaEnergiaResult result) {
        if (!positive(result.contaEstimada)) {
            return 'Não foi possível identificar o valor atual ou médio da conta para simulação.';
        }
        if (result.economiaMensal == null || result.economiaAnual == null || result.descontoPercent == null) {
            return 'Não foi possível calcular a simulação com as regras atuais do Salesforce.';
        }
        if (!positive(result.consumoTotalKwh)) {
            return 'Não foi possível calcular o consumo total com o valor da conta informado.';
        }
        if (!positive(result.kwhContratado)) {
            return 'Consumo informado dentro da disponibilidade mínima do padrão de rede selecionado.';
        }
        return 'Simulação calculada com o modelo do simulador de desconto de 15%.';
    }

    private static void persistSimulationFields(ContaEnergiaResult result) {
        if (result == null || result.propostaId == null || !positive(result.contaEstimada)) {
            return;
        }

        Proposta__c proposta = new Proposta__c(Id = result.propostaId);
        setIfNotNull(proposta, 'Tarifa_Kwh_com_impostos_R__c', result.tarifaKwhComImpostos);
        setIfNotNull(proposta, 'Iluminacao_Publica_R__c', result.iluminacaoPublica);
        setIfNotNull(proposta, 'Minimo_Distribuidora_KWh__c', result.disponibilidadeKwh);
        setIfNotNull(proposta, 'Consumo_Total_KWh__c', result.consumoTotalKwh);
        setIfNotNull(proposta, 'Compensavel_KWh__c', result.kwhContratado);
        setIfNotNull(proposta, 'Boleto_Distribuidora_R__c', result.boletoDistribuidora);
        setIfNotNull(proposta, 'Boleto_Gerador_Parceiro_R__c', result.boletoGeradorParceiro);
        setIfNotNull(proposta, 'Total_2_boletos__c', result.totalDoisBoletos);
        setIfNotNull(proposta, 'Deducoes__c', result.deducoes);
        setIfNotNull(proposta, 'Custo_total_R__c', result.contaEstimada);
        setIfNotNull(proposta, 'Custo_total_com_deducoes__c', result.custoTotalComDeducoes);
        setIfNotNull(proposta, 'Tarifa_com_desconto_R__c', result.tarifaComDesconto);
        setIfNotNull(proposta, 'Economia_Mensal_Simulador__c', result.economiaMensal);
        setIfNotNull(proposta, 'Economia_Anual__c', result.economiaAnual);
        setIfNotNull(proposta, 'Horario_de_Criacao_da_Simulacao__c', System.now());
        setIfNotNull(proposta, 'Usuario_Criador_da_Simulacao__c', currentUserDisplayName());

        Database.SaveResult saveResult = Database.update(proposta, false);
        if (!saveResult.isSuccess()) {
            safeLog('persistSimulationFields', 'Nao foi possivel salvar os campos do simulador de desconto na proposta.');
        }
    }

    private static String currentUserDisplayName() {
        String userName = '';
        if (!String.isBlank(UserInfo.getFirstName())) {
            userName = UserInfo.getFirstName().trim();
        }
        if (!String.isBlank(UserInfo.getLastName())) {
            userName += (String.isBlank(userName) ? '' : ' ') + UserInfo.getLastName().trim();
        }
        return String.isBlank(userName) ? UserInfo.getUserName() : userName;
    }

    private static String firstDmlError(Database.SaveResult result) {
        if (result == null || result.isSuccess() || result.getErrors().size() == 0) {
            return '';
        }
        Database.Error error = result.getErrors()[0];
        return String.valueOf(error.getStatusCode()) + ': ' + error.getMessage();
    }

    private static ContaEnergiaResult contaEnergiaError(String status, String message) {
        ContaEnergiaResult result = new ContaEnergiaResult();
        result.status = status;
        result.mensagem = message;
        result.hasRequiredEnergyData = false;
        result.hasRecognizedBillData = false;
        result.hasSimulationData = false;
        result.elegivel = false;
        result.simulationMessage = message;
        return result;
    }

    private static EnergyContext resolveEnergyContext(
        Id opportunityId,
        Id leadId,
        Boolean ensureProposta,
        String tipoLigacao
    ) {
        EnergyContext context = new EnergyContext();
        context.opportunityId = opportunityId;
        context.leadId = leadId;

        if (context.leadId != null) {
            context.lead = TotemOportunidadesSelector.getLeadForCustomer(context.leadId);
            if (context.opportunityId == null && context.lead != null && context.lead.ConvertedOpportunityId != null) {
                context.opportunityId = context.lead.ConvertedOpportunityId;
            }
        }

        if (context.opportunityId != null) {
            context.opportunity = loadOpportunity(context.opportunityId);
            if (context.opportunity != null && context.leadId == null && context.opportunity.Lead__c != null) {
                context.leadId = context.opportunity.Lead__c;
            }
        }

        if (context.lead == null && context.leadId != null) {
            context.lead = TotemOportunidadesSelector.getLeadForCustomer(context.leadId);
        }

        if (context.opportunity != null) {
            context.opportunityId = context.opportunity.Id;
            context.proposta = ensureProposta == true
                ? ensurePrimaryProposta(context.opportunity, context.lead, tipoLigacao)
                : findPrimaryProposta(context.opportunityId);
        }

        return context;
    }

    private static Opportunity loadOpportunity(Id opportunityId) {
        return TotemOportunidadesSelector.getOpportunityEnergy(opportunityId);
    }

    private static Lead loadLead(Id leadId, Id opportunityId) {
        Id resolvedLeadId = leadId;
        if (resolvedLeadId == null && opportunityId != null) {
            resolvedLeadId = TotemOportunidadesSelector.getOpportunityLeadId(opportunityId);
        }
        return TotemOportunidadesSelector.getLeadEnergy(resolvedLeadId);
    }

    private static Proposta__c findPrimaryProposta(Id opportunityId) {
        return TotemOportunidadesSelector.getPrimaryProposta(opportunityId);
    }

    private static Proposta__c ensurePrimaryProposta(Opportunity opp, Lead lead, String tipoLigacao) {
        if (opp == null || opp.Id == null) {
            return null;
        }

        Proposta__c proposta = findPrimaryProposta(opp.Id);
        if (proposta != null) {
            return proposta;
        }

        try {
            Proposta__c novaProposta = buildTotemProposta(opp, lead, tipoLigacao);
            Database.SaveResult result = Database.insert(novaProposta, false);
            if (!result.isSuccess()) {
                safeLog(
                    'ensurePrimaryProposta',
                    'Nao foi possivel criar Proposta__c para receber a fatura do totem. ' + firstDmlError(result)
                );
                return null;
            }

            Proposta__c created = findPrimaryProposta(opp.Id);
            return created == null ? novaProposta : created;
        } catch (Exception ex) {
            safeLog('ensurePrimaryProposta', 'Excecao ao criar Proposta__c para receber a fatura do totem. ' + ex.getMessage());
            return null;
        }
    }

    private static Proposta__c buildTotemProposta(Opportunity opp, Lead lead, String tipoLigacao) {
        Proposta__c proposta = new Proposta__c(
            Oportunidade__c = opp.Id,
            Conta__c = opp.AccountId,
            Titular__c = firstString(
                opp.Account == null ? null : opp.Account.Name,
                firstString(opp.Rep_Legal__r == null ? null : opp.Rep_Legal__r.Name, lead == null ? null : lead.Company)
            ),
            CPF_CNPJ__c = firstIdentity(
                opp.CNPJ__c,
                firstString(opp.Rep_Legal_CPF__c, opp.Rep_Legal__r == null ? null : opp.Rep_Legal__r.CPF__c),
                lead == null ? null : lead.CPF__c
            ),
            Distribuidora__c = opp.Distribuidora__c,
            Distribuidora_Id__c = opp.Distribuidora__c == null ? null : String.valueOf(opp.Distribuidora__c),
            Distribuidora_Nome__c = opp.Distribuidora_Nome__c,
            Padrao_da_Rede__c = firstString(padraoRedeFromKey(tipoLigacao), opp.PadraoRede__c)
        );

        if (opp.Custo_do_Lead__c != null) {
            proposta.Custo_total_R__c = opp.Custo_do_Lead__c;
        } else if (lead != null && lead.Custo__c != null) {
            proposta.Custo_total_R__c = lead.Custo__c;
        }

        return proposta;
    }

    private static void persistEnergyChoices(
        Id opportunityId,
        Id leadId,
        Id propostaId,
        Boolean hasSolar,
        String tipoLigacao,
        Boolean billReceived,
        Decimal monthlyCost,
        String faixaCusto
    ) {
        String padraoRede = padraoRedeFromKey(tipoLigacao);

        if (opportunityId != null) {
            Opportunity opp = new Opportunity(Id = opportunityId);
            if (hasSolar != null) {
                opp.PossuiEnergiaSolar__c = hasSolar;
            }
            if (!String.isBlank(padraoRede)) {
                opp.PadraoRede__c = padraoRede;
            }
            if (positive(monthlyCost)) {
                opp.Custo_do_Lead__c = monthlyCost;
                opp.Valor_da_Cobranca__c = monthlyCost;
            }
            if (!String.isBlank(faixaCusto)) {
                opp.Faixa_de_Custo__c = faixaCusto;
            }
            if (billReceived) {
                opp.Fatura_recebida__c = true;
                opp.Coleta_Fatura_Concluida__c = true;
            }
            Database.update(opp, false);
        }

        Lead leadContext = leadId == null ? null : TotemOportunidadesSelector.getLeadForCustomer(leadId);
        if (leadContext != null && leadContext.IsConverted != true) {
            Lead lead = new Lead(Id = leadId);
            if (hasSolar != null) {
                lead.PossuiEnergiaSolar__c = hasSolar;
            }
            if (!String.isBlank(padraoRede)) {
                lead.PadraoRede__c = padraoRede;
            }
            if (positive(monthlyCost)) {
                lead.Custo__c = monthlyCost;
            }
            if (!String.isBlank(faixaCusto)) {
                lead.Faixa_de_Custo__c = faixaCusto;
            }
            Database.update(lead, false);
        }

        if (propostaId != null) {
            Proposta__c proposta = new Proposta__c(Id = propostaId);
            if (!String.isBlank(padraoRede)) {
                proposta.Padrao_da_Rede__c = padraoRede;
            }
            if (positive(monthlyCost)) {
                proposta.Custo_total_R__c = monthlyCost;
            }
            Database.update(proposta, false);
        }
    }

    private static Boolean hasRequiredOcrData(Proposta_OCR_Fatura_V2.infoOCR ocr) {
        if (ocr == null) {
            return false;
        }
        Boolean hasInstallation = !String.isBlank(firstString(ocr.numero_da_instalacao, ocr.numero_uc));
        Boolean hasConsumption = positive(firstDecimal(new List<Object>{ ocr.kwh_medio, ocr.consumo_medio_kwh }));
        return hasInstallation && hasConsumption;
    }

    private static Proposta__c buildPropostaFromOcr(
        Id propostaId,
        Proposta_OCR_Fatura_V2.infoOCR ocr,
        String tipoLigacao
    ) {
        Proposta__c updateProposta = new Proposta__c(Id = propostaId);
        setIfNotBlank(updateProposta, 'Numero_do_Cliente__c', firstString(ocr.numero_do_cliente, ocr.numero_cliente));
        setIfNotBlank(updateProposta, 'Numero_da_Instalacao__c', firstString(ocr.numero_da_instalacao, ocr.numero_uc));
        setIfNotBlank(updateProposta, 'Titular__c', firstString(ocr.Titular, ocr.nome));
        setIfNotBlank(updateProposta, 'CPF_CNPJ__c', ocr.cpf_cnpj);
        setIfNotBlank(updateProposta, 'Grupo_Tarifario__c', ocr.grupo_tarifario);
        setIfNotBlank(updateProposta, 'Padrao_da_Rede__c', firstString(padraoRedeFromKey(tipoLigacao), ocr.padrao_da_rede));
        setIfNotNull(updateProposta, 'Data_do_Vencimento__c', parseDate(firstString(ocr.data_de_vencimento, ocr.vencimento_da_fatura_dt)));
        setIfNotNull(updateProposta, 'Data_da_Leitura__c', parseDate(firstString(ocr.data_da_leitura_atual, ocr.leitura_atual_dt)));
        setIfNotNull(updateProposta, 'kWh_Medio__c', firstDecimal(new List<Object>{ ocr.kwh_medio, ocr.consumo_medio_kwh }));
        setIfNotNull(updateProposta, 'Custo_total_R__c', firstDecimal(new List<Object>{ ocr.valor_a_pagar }));
        setIfNotBlank(updateProposta, 'Numero__c', ocr.numero);
        setIfNotBlank(updateProposta, 'Logradouro__c', ocr.logradouro);
        setIfNotBlank(updateProposta, 'Complemento__c', ocr.complemento);
        setIfNotBlank(updateProposta, 'Bairro__c', ocr.bairro);
        setIfNotBlank(updateProposta, 'Cidade__c', ocr.cidade);
        setIfNotBlank(updateProposta, 'UF__c', firstString(ocr.uf, ocr.estado));
        setIfNotBlank(updateProposta, 'CEP__c', ocr.cep);
        setIfNotNull(updateProposta, 'CIP__c', firstDecimal(new List<Object>{ ocr.cip }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_01__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_01, ocr.consumo_kwh_01 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_02__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_02, ocr.consumo_kwh_02 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_03__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_03, ocr.consumo_kwh_03 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_04__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_04, ocr.consumo_kwh_04 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_05__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_05, ocr.consumo_kwh_05 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_06__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_06, ocr.consumo_kwh_06 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_07__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_07, ocr.consumo_kwh_07 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_08__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_08, ocr.consumo_kwh_08 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_09__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_09, ocr.consumo_kwh_09 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_10__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_10, ocr.consumo_kwh_10 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_11__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_11, ocr.consumo_kwh_11 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_12__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_12, ocr.consumo_kwh_12 }));
        setIfNotNull(updateProposta, 'kWh_Consumo_Mes_13__c', firstDecimal(new List<Object>{ ocr.kwh_consumo_13, ocr.consumo_kwh_13 }));
        return updateProposta;
    }

    private static void setIfNotBlank(SObject record, String fieldName, String value) {
        if (!String.isBlank(value)) {
            record.put(fieldName, value.trim());
        }
    }

    private static void setIfNotNull(SObject record, String fieldName, Object value) {
        if (value != null) {
            record.put(fieldName, value);
        }
    }

    private static String padraoRedeFromKey(String key) {
        if (key == 'mono') {
            return 'Monofásico';
        }
        if (key == 'bi') {
            return 'Bifásico';
        }
        if (key == 'tri') {
            return 'Trifásico';
        }
        return null;
    }

    private static String ligacaoKeyFromPadrao(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String normalized = value.trim().toLowerCase();
        if (normalized.startsWith('mono')) {
            return 'mono';
        }
        if (normalized.startsWith('bi')) {
            return 'bi';
        }
        if (normalized.startsWith('tri')) {
            return 'tri';
        }
        return null;
    }

    private static Decimal firstDecimal(List<Object> values) {
        for (Object value : values) {
            Decimal result = decimalValue(value);
            if (result != null) {
                return result;
            }
        }
        return null;
    }

    private static Decimal decimalValue(Object value) {
        if (value == null) {
            return null;
        }
        try {
            Decimal result = Decimal.valueOf(String.valueOf(value));
            return result;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean positive(Decimal value) {
        return value != null && value > 0;
    }

    private static String firstString(String first, String second) {
        if (!String.isBlank(first)) {
            return first.trim();
        }
        return String.isBlank(second) ? null : second.trim();
    }

    private static String firstIdentity(String first, String second, String third) {
        for (String value : new List<String>{ first, second, third }) {
            if (!String.isBlank(onlyDigits(value))) {
                return value.trim();
            }
        }
        return null;
    }

    private static String sanitizeFileName(String value) {
        String normalized = String.isBlank(value) ? 'conta-energia.pdf' : value.trim();
        normalized = normalized.replaceAll('[\\\\/<>:"|?*]+', '-');
        return normalized.length() > 180 ? normalized.substring(normalized.length() - 180) : normalized;
    }

    private static String extensionFromFileName(String value) {
        if (String.isBlank(value) || !value.contains('.')) {
            return null;
        }
        return value.substring(value.lastIndexOf('.') + 1).toLowerCase();
    }

    private static String cleanBase64(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        Integer commaIndex = value.indexOf(',');
        return commaIndex >= 0 ? value.substring(commaIndex + 1) : value.trim();
    }

    private static Integer estimateBase64Bytes(String value) {
        String cleaned = cleanBase64(value);
        if (String.isBlank(cleaned)) {
            return 0;
        }
        Integer padding = 0;
        if (cleaned.endsWith('==')) {
            padding = 2;
        } else if (cleaned.endsWith('=')) {
            padding = 1;
        }
        return ((cleaned.length() * 3) / 4) - padding;
    }

    private static AdesaoResult resolverCadastroCliente(AdesaoRequest req, String methodName) {
        if (req.opportunityId != null) {
            return processarOportunidadeExistente(req.opportunityId, req);
        }

        if (req.leadId != null) {
            return processarLeadExistente(req.leadId, req);
        }

        CadastroCandidate duplicate = findDuplicateForSubmit(req);
        if (duplicate != null) {
            if (duplicate.isClosedOpportunity()) {
                safeLog(methodName, 'Cadastro encerrado encontrado antes de criar novo cliente.');
                throw new AuraHandledException('Cliente ja possui uma adesao encerrada. Nao foi criado novo cadastro automaticamente.');
            }
            if (duplicate.isOpenOpportunity()) {
                return processarOportunidadeExistente(duplicate.opportunity.Id, req);
            }
            if (duplicate.isUnconvertedLead()) {
                return processarLeadExistente(duplicate.lead.Id, req);
            }
        }

        return criarNovoLead(req);
    }

    private static LocalizarCadastroResult localizarPorCodigo(LocalizarCadastroRequest req) {
        LocalizarCadastroResult result = new LocalizarCadastroResult();
        result.matches = new List<CadastroMatch>();
        result.nextStep = 1;
        result.canCreateNew = false;
        result.validatedByCode = false;

        Set<String> codeCandidates = buildCodeCandidates(req.searchValue);
        if (codeCandidates.isEmpty()) {
            result.status = 'INVALID_CODE';
            result.mensagem = 'Codigo invalido.';
            return result;
        }

        List<Lead> leads = TotemOportunidadesSelector.getLeadsByCodes(codeCandidates, 20);

        Integer validityDays = normalizeValidityDays(req.codeValidityDays);
        Datetime oldestValidDate = System.now().addDays(-validityDays);
        List<Lead> validLeads = new List<Lead>();
        for (Lead lead : leads) {
            if (lead.CreatedDate >= oldestValidDate) {
                validLeads.add(lead);
            }
        }

        if (validLeads.isEmpty()) {
            result.status = 'INVALID_CODE';
            result.mensagem = 'Codigo invalido ou expirado.';
            return result;
        }

        List<CadastroCandidate> candidates = buildCandidates(validLeads, new List<Contact>());
        LocalizarCadastroResult resolved = resolveCandidates(candidates, req.cpf, true);
        if (resolved.status == 'OPEN_OPPORTUNITY' || resolved.status == 'LEAD_FOUND') {
            markValidatedByCode(resolved.leadId, resolved.opportunityId);
            resolved.validatedByCode = true;
        }
        if (resolved.status == 'NOT_FOUND') {
            resolved.status = 'INVALID_CODE';
            resolved.mensagem = 'Codigo invalido ou expirado.';
        }
        return resolved;
    }

    private static LocalizarCadastroResult localizarPorWhatsapp(LocalizarCadastroRequest req) {
        LocalizarCadastroResult result = new LocalizarCadastroResult();
        result.matches = new List<CadastroMatch>();

        String comparablePhone = normalizePhoneComparable(req.searchValue);
        if (String.isBlank(comparablePhone) || comparablePhone.length() < 10) {
            result.status = 'INVALID_INPUT';
            result.mensagem = 'Informe DDD e numero de WhatsApp.';
            return result;
        }

        String lastDigits = comparablePhone.right(Math.min(8, comparablePhone.length()));
        String likePattern = '%' + lastDigits + '%';

        List<Lead> rawLeads = TotemOportunidadesSelector.getLeadsByPhoneLike(likePattern, MAX_SEARCH_RESULTS);
        List<Lead> leads = new List<Lead>();
        for (Lead lead : rawLeads) {
            if (normalizePhoneComparable(lead.MobilePhone) == comparablePhone) {
                leads.add(lead);
            }
        }

        List<Contact> rawContacts = TotemOportunidadesSelector.getContactsByPhoneLike(likePattern, MAX_SEARCH_RESULTS);
        List<Contact> contacts = new List<Contact>();
        for (Contact contact : rawContacts) {
            if (normalizePhoneComparable(contact.MobilePhone) == comparablePhone) {
                contacts.add(contact);
            }
        }

        return resolveCandidates(buildCandidates(leads, contacts), req.cpf, false);
    }

    private static LocalizarCadastroResult localizarPorEmail(LocalizarCadastroRequest req) {
        LocalizarCadastroResult result = new LocalizarCadastroResult();
        result.matches = new List<CadastroMatch>();

        String email = normalizeEmail(req.searchValue);
        if (String.isBlank(email) || !email.contains('@')) {
            result.status = 'INVALID_INPUT';
            result.mensagem = 'Informe um e-mail valido.';
            return result;
        }

        List<Lead> leads = TotemOportunidadesSelector.getLeadsByEmail(email, MAX_SEARCH_RESULTS);

        List<Contact> contacts = TotemOportunidadesSelector.getContactsByEmail(email, MAX_SEARCH_RESULTS);

        return resolveCandidates(buildCandidates(leads, contacts), req.cpf, false);
    }

    private static List<CadastroCandidate> buildCandidates(List<Lead> leads, List<Contact> contacts) {
        Map<Id, Lead> leadById = new Map<Id, Lead>();
        Set<Id> leadIds = new Set<Id>();
        Set<Id> convertedOpportunityIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (Lead lead : leads) {
            leadById.put(lead.Id, lead);
            leadIds.add(lead.Id);
            if (lead.IsConverted && lead.ConvertedOpportunityId != null) {
                convertedOpportunityIds.add(lead.ConvertedOpportunityId);
            }
        }
        for (Contact contact : contacts) {
            contactIds.add(contact.Id);
        }

        Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>();
        if (!convertedOpportunityIds.isEmpty() || !leadIds.isEmpty()) {
            for (Opportunity opp : TotemOportunidadesSelector.getOpportunitiesByLeadIdsOrIds(
                convertedOpportunityIds,
                leadIds,
                MAX_SEARCH_RESULTS
            )) {
                opportunities.put(opp.Id, opp);
            }
        }
        if (!contactIds.isEmpty()) {
            for (Opportunity opp : TotemOportunidadesSelector.getOpportunitiesByContactIds(
                contactIds,
                MAX_SEARCH_RESULTS
            )) {
                opportunities.put(opp.Id, opp);
            }
        }

        List<CadastroCandidate> candidates = new List<CadastroCandidate>();
        for (Opportunity opp : opportunities.values()) {
            candidates.add(new CadastroCandidate(opp));
        }
        for (Lead lead : leads) {
            if (!lead.IsConverted) {
                candidates.add(new CadastroCandidate(lead));
            }
        }
        return candidates;
    }

    private static LocalizarCadastroResult resolveCandidates(List<CadastroCandidate> candidates, String cpf, Boolean isCodeSearch) {
        LocalizarCadastroResult result = new LocalizarCadastroResult();
        result.matches = new List<CadastroMatch>();
        result.nextStep = 1;
        result.canCreateNew = false;
        result.validatedByCode = false;

        List<CadastroCandidate> filtered = filterByCpf(candidates, cpf);
        if (filtered.isEmpty()) {
            result.status = 'NOT_FOUND';
            result.mensagem = 'Cadastro nao encontrado.';
            result.canCreateNew = !isCodeSearch;
            return result;
        }

        filtered.sort(new CadastroCandidateSorter());

        if (!isCodeSearch && filtered.size() > 1 && String.isBlank(onlyDigits(cpf))) {
            result.status = 'NEEDS_CPF';
            result.mensagem = 'Mais de um cadastro encontrado. Confirme o CPF para continuar.';
            result.matches = buildMaskedMatches(filtered);
            return result;
        }

        CadastroCandidate selected = filtered[0];
        fillResultFromCandidate(result, selected);
        if (selected.isOpenOpportunity()) {
            result.status = 'OPEN_OPPORTUNITY';
            result.mensagem = 'Oportunidade aberta localizada.';
        } else if (selected.isUnconvertedLead()) {
            result.status = 'LEAD_FOUND';
            result.mensagem = 'Lead localizado para continuidade.';
        } else {
            result.status = 'CLOSED_OPPORTUNITY';
            result.mensagem = 'Cliente ja possui uma adesao encerrada.';
            result.nextStep = 1;
            safeLog('resolveCandidates', 'Oportunidade encerrada localizada no totem.');
        }
        return result;
    }

    private class CadastroCandidateSorter implements System.Comparator<CadastroCandidate> {
        public Integer compare(CadastroCandidate left, CadastroCandidate right) {
            Integer leftPriority = left.priority();
            Integer rightPriority = right.priority();
            if (leftPriority == rightPriority) {
                return 0;
            }
            return leftPriority < rightPriority ? -1 : 1;
        }
    }

    private static List<CadastroCandidate> filterByCpf(List<CadastroCandidate> candidates, String cpf) {
        String cpfDigits = onlyDigits(cpf);
        if (String.isBlank(cpfDigits)) {
            return candidates;
        }

        List<CadastroCandidate> filtered = new List<CadastroCandidate>();
        for (CadastroCandidate candidate : candidates) {
            if (onlyDigits(candidate.cpf()) == cpfDigits) {
                filtered.add(candidate);
            }
        }
        return filtered;
    }

    private static List<CadastroMatch> buildMaskedMatches(List<CadastroCandidate> candidates) {
        List<CadastroMatch> matches = new List<CadastroMatch>();
        Integer index = 0;
        for (CadastroCandidate candidate : candidates) {
            if (index >= 3) {
                break;
            }
            CadastroMatch match = new CadastroMatch();
            match.key = String.valueOf(index);
            match.recordType = candidate.recordType;
            match.maskedName = maskName(candidate.nomeCompleto());
            match.maskedEmail = maskEmail(candidate.email());
            match.maskedWhatsapp = maskPhone(candidate.whatsapp());
            matches.add(match);
            index++;
        }
        return matches;
    }

    private static void fillResultFromCandidate(LocalizarCadastroResult result, CadastroCandidate candidate) {
        result.leadId = candidate.lead != null ? candidate.lead.Id : null;
        result.opportunityId = candidate.opportunity != null ? candidate.opportunity.Id : null;
        result.nextStep = 2;
        result.nomeCompleto = candidate.nomeCompleto();
        result.cpf = candidate.cpf();
        Date birthDate = candidate.dataNasc();
        result.dataNasc = birthDate == null ? null : String.valueOf(birthDate);
        result.whatsapp = candidate.whatsapp();
        result.email = candidate.email();
    }

    private static AdesaoResult processarOportunidadeExistente(Id opportunityId, AdesaoRequest req) {
        Opportunity opp = TotemOportunidadesSelector.getOpportunityForCustomer(opportunityId);
        if (opp == null) {
            throw new AuraHandledException('Oportunidade nao encontrada.');
        }

        if (opp.IsClosed) {
            safeLog('processarOportunidadeExistente', 'Tentativa de alterar oportunidade encerrada bloqueada.');
            throw new AuraHandledException('Cliente ja possui uma adesao encerrada.');
        }

        fillRequestFromCandidate(req, new CadastroCandidate(opp));
        updateContactFromRequest(opp.Rep_Legal__c, req);
        updateLeadIfAvailable(opp.Lead__c, req);

        AdesaoResult result = new AdesaoResult();
        result.sucesso = true;
        result.leadId = opp.Lead__c;
        result.opportunityId = opp.Id;
        result.codigoUnico = resolveCodeForLead(opp.Lead__c, opp.Id);
        result.mensagem = 'Oportunidade existente carregada.';
        return result;
    }

    private static AdesaoResult finalizarAdesaoOportunidade(AdesaoRequest req) {
        System.debug('finalizarAdesaoOportunidade: ' + JSON.serializePretty(req));
        Id opportunityId = req == null ? null : req.opportunityId;
        if (opportunityId == null && req != null && req.leadId != null) {
            Lead lead = TotemOportunidadesSelector.getLeadForCustomer(req.leadId);
            if (lead != null && lead.ConvertedOpportunityId != null) {
                opportunityId = lead.ConvertedOpportunityId;
                req.opportunityId = opportunityId;
            }
        }
        if (opportunityId == null && req != null) {
            CadastroCandidate candidate = findDuplicateForSubmit(req);
            if (candidate != null && candidate.isOpenOpportunity()) {
                opportunityId = candidate.opportunity.Id;
                req.opportunityId = opportunityId;
                if (req.leadId == null) {
                    req.leadId = candidate.opportunity.Lead__c;
                }
            }
        }

        if (opportunityId == null) {
            throw new AuraHandledException('Oportunidade nao encontrada para finalizar a adesao.');
        }

        Opportunity opp = TotemOportunidadesSelector.getOpportunityForCustomer(opportunityId);
        if (opp == null) {
            throw new AuraHandledException('Oportunidade nao encontrada.');
        }
        if (opp.IsClosed) {
            safeLog('finalizarAdesaoOportunidade', 'Tentativa de finalizar oportunidade encerrada bloqueada.');
            throw new AuraHandledException('Cliente ja possui uma adesao encerrada.');
        }

        Id leadId = req.leadId == null ? opp.Lead__c : req.leadId;
        req.leadId = leadId;
        fillRequestFromCandidate(req, new CadastroCandidate(opp));

        persistFinalSimulation(req, opportunityId, leadId);
        updateContactFromRequest(opp.Rep_Legal__c, req);
        updateLeadIfAvailable(leadId, req);

        AdesaoResult result = new AdesaoResult();
        result.sucesso = true;
        result.leadId = leadId;
        result.opportunityId = opportunityId;
        result.codigoUnico = ensureOpportunityCode(opportunityId, leadId);
        result.mensagem = 'Adesao registrada com sucesso.';
        return result;
    }

    private static void persistFinalSimulation(AdesaoRequest req, Id opportunityId, Id leadId) {
        EnergyContext context = resolveEnergyContext(opportunityId, leadId, true, req.tipoLigacao);
        Decimal normalizedMonthlyCost = positive(req.monthlyCost)
            ? req.monthlyCost
            : monthlyCostFromFaixaCusto(req.energyRange);

        persistEnergyChoices(
            context.opportunityId,
            context.leadId,
            context.proposta == null ? null : context.proposta.Id,
            req.hasSolar,
            req.tipoLigacao,
            false,
            normalizedMonthlyCost,
            req.energyRange
        );

        ContaEnergiaResult energyResult = carregarDadosContaEnergia(context.opportunityId, context.leadId);
        if (positive(normalizedMonthlyCost)) {
            energyResult.monthlyCost = normalizedMonthlyCost;
            energyResult.contaEstimada = normalizedMonthlyCost;
            applySimulationData(energyResult);
        }
        persistSimulationFields(energyResult);
    }

    private static void updateLeadIfAvailable(Id leadId, AdesaoRequest req) {
        if (leadId == null) {
            return;
        }

        try {
            Lead lead = TotemOportunidadesSelector.getLeadForCustomer(leadId);
            if (lead == null) {
                return;
            }
            updateLeadFromRequest(lead, req);
            update lead;
        } catch (Exception ex) {
            safeLog('updateLeadIfAvailable', 'Nao foi possivel atualizar Lead vinculado a oportunidade.');
        }
    }

    private static AdesaoResult processarLeadExistente(Id leadId, AdesaoRequest req) {
        Lead lead = TotemOportunidadesSelector.getLeadForCustomer(leadId);
        if (lead == null) {
            throw new AuraHandledException('Lead nao encontrado.');
        }

        fillRequestFromCandidate(req, new CadastroCandidate(lead));
        validateDadosCliente(req);
        updateLeadFromRequest(lead, req);
        update lead;

        AdesaoResult result = new AdesaoResult();
        result.leadId = lead.Id;
        result.codigoUnico = ensureLeadCode(lead);

        if ( lead.ConvertedOpportunityId != null) {
            result.sucesso = true;
            result.opportunityId = lead.ConvertedOpportunityId;
            result.mensagem = 'Lead ja convertido.';
            linkOpportunityToLead(result.opportunityId, lead.Id);
            return result;
        }

        converterLead(lead.Id, result);
        return result;
    }

    private static AdesaoResult criarNovoLead(AdesaoRequest req) {
        Lead lead = buildLead(req);
        insert lead;

        AdesaoResult result = new AdesaoResult();
        result.leadId = lead.Id;
        result.codigoUnico = ensureLeadCode(lead);
        result.sucesso = true;
        result.leadCriado = true;
        result.mensagem = 'Dados confirmados. Clique em Confirmar dados novamente para seguir com a simulação.';
        return result;
    }

    private static Lead buildLead(AdesaoRequest req) {
        Map<String, String> names = splitName(req.nomeCompleto);
        Lead lead = new Lead(
            FirstName   = String.isBlank(names.get('firstName')) ? null : names.get('firstName'),
            LastName    = names.get('lastName'),
            Company     = req.nomeCompleto.trim(),
            Email       = normalizeEmail(req.email),
            MobilePhone = String.isBlank(req.whatsapp) ? null : req.whatsapp.trim(),
            LeadSource  = normalizeText(req.leadSource, 'Totem Oportunidades', 80),
            Custo__c    = req.monthlyCost
        );
        updateLeadFromRequest(lead, req);
        return lead;
    }

    private static void updateLeadFromRequest(Lead lead, AdesaoRequest req) {
        Map<String, String> names = splitName(req.nomeCompleto);
        lead.FirstName = String.isBlank(names.get('firstName')) ? null : names.get('firstName');
        lead.LastName = names.get('lastName');
        lead.Company = req.nomeCompleto.trim();
        lead.Email = normalizeEmail(req.email);
        lead.MobilePhone = String.isBlank(req.whatsapp) ? null : req.whatsapp.trim();
        lead.LeadSource = normalizeText(req.leadSource, 'Totem Oportunidades', 80);
        if (req.monthlyCost != null) {
            lead.Custo__c = req.monthlyCost;
        }

        Map<String, Schema.SObjectField> fields = Lead.getSObjectType().getDescribe().fields.getMap();
        if (!String.isBlank(req.cpf) && fields.containsKey('CPF__c')) {
            lead.put('CPF__c', onlyDigits(req.cpf));
        }
        if (!String.isBlank(req.dataNasc) && fields.containsKey('Data_de_Nascimento__c')) {
            Date parsedDate = parseDate(req.dataNasc);
            if (parsedDate != null) {
                lead.put('Data_de_Nascimento__c', parsedDate);
            }
        }
        if (req.aceitaContato != null && fields.containsKey('Aceita_Contato__c')) {
            lead.put('Aceita_Contato__c', req.aceitaContato);
        }
        if (req.aceitaPoliticaPrivacidade != null && fields.containsKey('Aceita_Politica_de_Privacidade__c')) {
            lead.put('Aceita_Politica_de_Privacidade__c', req.aceitaPoliticaPrivacidade);
        }
        if (!String.isBlank(req.formWeb) && fields.containsKey('Form_Web__c')) {
            lead.put('Form_Web__c', normalizeText(req.formWeb, null, 80));
        }
        if (!String.isBlank(req.campaignCode) && fields.containsKey('utm_campaign__c')) {
            lead.put('utm_campaign__c', normalizeText(req.campaignCode, null, 255));
        }
        if (!String.isBlank(req.leadOrigin) && fields.containsKey('utm_source__c')) {
            lead.put('utm_source__c', normalizeText(req.leadOrigin, null, 255));
        }
        if (!String.isBlank(req.partnerCode) && fields.containsKey('Parceiro_na_vertical__c')) {
            lead.put('Parceiro_na_vertical__c', normalizeText(req.partnerCode, null, 255));
        }
    }

    private static void updateContactFromRequest(Id contactId, AdesaoRequest req) {
        if (contactId == null) {
            return;
        }

        Contact contactToUpdate = new Contact(Id = contactId);
        Map<String, String> names = splitName(req.nomeCompleto);
        contactToUpdate.FirstName = String.isBlank(names.get('firstName')) ? null : names.get('firstName');
        contactToUpdate.LastName = names.get('lastName');
        contactToUpdate.Email = normalizeEmail(req.email);
        contactToUpdate.MobilePhone = String.isBlank(req.whatsapp) ? null : req.whatsapp.trim();
        if (!String.isBlank(req.cpf)) {
            contactToUpdate.CPF__c = onlyDigits(req.cpf);
        }
        Date parsedDate = parseDate(req.dataNasc);
        if (parsedDate != null) {
            contactToUpdate.Data_de_Nascimento__c = parsedDate;
        }
        Map<String, Schema.SObjectField> fields = Contact.getSObjectType().getDescribe().fields.getMap();
        if (req.aceitaContato != null && fields.containsKey('Aceita_Contato__c')) {
            contactToUpdate.put('Aceita_Contato__c', req.aceitaContato);
        }
        if (req.aceitaPoliticaPrivacidade != null && fields.containsKey('Aceita_Politica_de_Privacidade__c')) {
            contactToUpdate.put('Aceita_Politica_de_Privacidade__c', req.aceitaPoliticaPrivacidade);
        }

        try {
            update contactToUpdate;
        } catch (Exception ex) {
            safeLog('updateContactFromRequest', 'Nao foi possivel atualizar dados basicos do contato.');
        }
    }

    private static CadastroCandidate findDuplicateForSubmit(AdesaoRequest req) {
        List<CadastroCandidate> candidates = new List<CadastroCandidate>();

        if (!String.isBlank(req.email)) {
            LocalizarCadastroRequest emailReq = new LocalizarCadastroRequest();
            emailReq.searchType = SEARCH_EMAIL;
            emailReq.searchValue = req.email;
            emailReq.cpf = req.cpf;
            LocalizarCadastroResult emailResult = localizarPorEmail(emailReq);
            CadastroCandidate emailCandidate = candidateFromResult(emailResult);
            if (emailCandidate != null) {
                candidates.add(emailCandidate);
            }
        }

        if (!String.isBlank(req.whatsapp)) {
            LocalizarCadastroRequest phoneReq = new LocalizarCadastroRequest();
            phoneReq.searchType = SEARCH_WHATSAPP;
            phoneReq.searchValue = req.whatsapp;
            phoneReq.cpf = req.cpf;
            LocalizarCadastroResult phoneResult = localizarPorWhatsapp(phoneReq);
            CadastroCandidate phoneCandidate = candidateFromResult(phoneResult);
            if (phoneCandidate != null) {
                candidates.add(phoneCandidate);
            }
        }

        if (candidates.isEmpty()) {
            return null;
        }
        candidates.sort(new CadastroCandidateSorter());
        return candidates[0];
    }

    private static CadastroCandidate candidateFromResult(LocalizarCadastroResult result) {
        if (result == null || (result.opportunityId == null && result.leadId == null)) {
            return null;
        }
        if (result.opportunityId != null) {
            Opportunity opp = TotemOportunidadesSelector.getOpportunityCandidate(result.opportunityId);
            return opp == null ? null : new CadastroCandidate(opp);
        }
        Lead lead = TotemOportunidadesSelector.getLeadCandidate(result.leadId);
        return lead == null ? null : new CadastroCandidate(lead);
    }

    private static void hydrateAdesaoRequest(AdesaoRequest req) {
        if (req == null) {
            return;
        }

        if (req.opportunityId != null) {
            Opportunity opp = TotemOportunidadesSelector.getOpportunityCandidate(req.opportunityId);
            if (opp != null) {
                fillRequestFromCandidate(req, new CadastroCandidate(opp));
                if (req.leadId == null) {
                    req.leadId = opp.Lead__c;
                }
            }
        }

        if (req.leadId != null) {
            Lead lead = TotemOportunidadesSelector.getLeadCandidate(req.leadId);
            if (lead != null) {
                fillRequestFromCandidate(req, new CadastroCandidate(lead));
                if (req.opportunityId == null && lead.ConvertedOpportunityId != null) {
                    req.opportunityId = lead.ConvertedOpportunityId;
                }
            }
        }
    }

    private static void fillRequestFromCandidate(AdesaoRequest req, CadastroCandidate candidate) {
        if (req == null || candidate == null) {
            return;
        }

        if (String.isBlank(req.nomeCompleto)) {
            req.nomeCompleto = candidate.nomeCompleto();
        }
        if (String.isBlank(req.cpf)) {
            req.cpf = candidate.cpf();
        }
        if (String.isBlank(req.dataNasc) && candidate.dataNasc() != null) {
            req.dataNasc = String.valueOf(candidate.dataNasc());
        }
        if (String.isBlank(req.whatsapp)) {
            req.whatsapp = candidate.whatsapp();
        }
        if (String.isBlank(req.email)) {
            req.email = candidate.email();
        }
    }

    private static void validateAdesao(AdesaoRequest req) {
        if (req == null) {
            throw new AuraHandledException('Dados nao informados.');
        }
        if (req.aceitaTermos != true) {
            throw new AuraHandledException('Aceite dos Termos e Condicoes e obrigatorio.');
        }
    }

    private static void validateDadosCliente(AdesaoRequest req) {
        if (req == null) {
            throw new AuraHandledException('Dados nao informados.');
        }
        if (String.isBlank(req.nomeCompleto)) {
            throw new AuraHandledException('Nome completo e obrigatorio.');
        }
        if (String.isBlank(req.cpf)) {
            throw new AuraHandledException('CPF e obrigatorio.');
        }
        if (String.isBlank(req.dataNasc)) {
            throw new AuraHandledException('Data de nascimento e obrigatoria.');
        }
        if (String.isBlank(req.whatsapp)) {
            throw new AuraHandledException('WhatsApp e obrigatorio.');
        }
        if (String.isBlank(req.email)) {
            throw new AuraHandledException('E-mail e obrigatorio.');
        }
    }

    private static void converterLead(Id leadId, AdesaoResult result) {
        try {
            String convertedStatus = TotemOportunidadesSelector.getConvertedLeadStatus();
            if (String.isBlank(convertedStatus)) {
                result.sucesso = false;
                result.erroConversao = 'Status de conversao de Lead nao encontrado.';
                result.mensagem = 'Nao foi possivel converter o Lead neste momento.';
                return;
            }

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(false);

            Database.LeadConvertResult lcr = Database.convertLead(lc);

            if (lcr.isSuccess()) {
                result.opportunityId = resolveConvertedOpportunityId(leadId, lcr.getOpportunityId());
                if (result.opportunityId == null) {
                    result.sucesso = false;
                    result.erroConversao = 'Lead convertido sem retorno de Opportunity.';
                    result.mensagem = 'Nao foi possivel recuperar a oportunidade criada na conversao do Lead.';
                    return;
                }
                result.sucesso = true;
                result.mensagem = 'Adesao registrada com sucesso.';
                linkOpportunityToLead(result.opportunityId, leadId);
            } else {
                String errorMessage = firstLeadConvertError(lcr);
                if (isWorkflowRecordInUse(errorMessage)) {
                    markConversionPending(result, errorMessage);
                    return;
                }
                result.sucesso = false;
                result.erroConversao = errorMessage;
                result.mensagem = 'Nao foi possivel converter o Lead neste momento.';
            }
        } catch (Exception ex) {
            String errorMessage = ex.getMessage();
            if (isWorkflowRecordInUse(errorMessage)) {
                markConversionPending(result, errorMessage);
                return;
            }
            safeLog('converterLead', 'Falha tecnica durante conversao de Lead. ' + errorMessage);
            result.sucesso = false;
            result.erroConversao = errorMessage;
            result.mensagem = 'Nao foi possivel converter o Lead neste momento.';
        }
    }

    private static void markConversionPending(AdesaoResult result, String errorMessage) {
        safeLog('converterLead', 'Conversao pendente por workflow lock. ' + errorMessage);
        result.sucesso = false;
        result.conversaoPendente = true;
        result.erroConversao = errorMessage;
        result.mensagem = 'Conversao do Lead aguardando liberacao do workflow.';
    }

    private static Boolean isWorkflowRecordInUse(String errorMessage) {
        return !String.isBlank(errorMessage) && errorMessage.contains('RECORD_IN_USE_BY_WORKFLOW');
    }

    private static String firstLeadConvertError(Database.LeadConvertResult result) {
        if (result == null || result.isSuccess() || result.getErrors().size() == 0) {
            return '';
        }
        Database.Error error = result.getErrors()[0];
        return String.valueOf(error.getStatusCode()) + ': ' + error.getMessage();
    }

    private static Id resolveConvertedOpportunityId(Id leadId, Id convertedOpportunityId) {
        if (convertedOpportunityId != null) {
            return convertedOpportunityId;
        }

        Lead lead = TotemOportunidadesSelector.getLeadCandidate(leadId);
        if (lead != null && lead.ConvertedOpportunityId != null) {
            return lead.ConvertedOpportunityId;
        }

        List<Opportunity> opportunities = TotemOportunidadesSelector.getOpportunitiesByLeadIdsOrIds(
            new Set<Id>(),
            new Set<Id>{ leadId },
            1
        );
        return opportunities.isEmpty() ? null : opportunities[0].Id;
    }

    private static String conversionFailureMessage(AdesaoResult result) {
        if (result != null && !String.isBlank(result.erroConversao)) {
            safeLog('confirmarDadosCliente', 'Falha ao converter Lead. ' + result.erroConversao);
        }
        return 'Nao foi possivel converter o Lead e gerar a oportunidade.';
    }

    private static void linkOpportunityToLead(Id opportunityId, Id leadId) {
        if (opportunityId == null || leadId == null) {
            return;
        }
        try {
            Lead lead = TotemOportunidadesSelector.getLeadEnergyForCopy(leadId);
            if (lead == null) {
                return;
            }

            Opportunity opp = new Opportunity(
                Id = opportunityId,
                Lead__c = leadId,
                PossuiEnergiaSolar__c = lead.PossuiEnergiaSolar__c
            );
            String code = ensureLeadCode(lead);
            if (!String.isBlank(code)) {
                opp.Codigo_no_Parceiro__c = code;
            }
            if (!String.isBlank(lead.PadraoRede__c)) {
                opp.PadraoRede__c = lead.PadraoRede__c;
            }
            if (!String.isBlank(lead.Faixa_de_Custo__c)) {
                opp.Faixa_de_Custo__c = lead.Faixa_de_Custo__c;
            }
            update opp;
        } catch (Exception ex) {
            safeLog('linkOpportunityToLead', 'Nao foi possivel vincular oportunidade ao Lead convertido ou copiar dados de energia.');
        }
    }

    private static String ensureOpportunityCode(Id opportunityId, Id leadId) {
        if (opportunityId == null) {
            return null;
        }

        Opportunity opp = TotemOportunidadesSelector.getOpportunityCode(opportunityId);
        if (opp != null && !String.isBlank(opp.Codigo_no_Parceiro__c)) {
            return opp.Codigo_no_Parceiro__c;
        }

        String code = null;
        if (leadId != null) {
            Lead lead = TotemOportunidadesSelector.getLeadCode(leadId);
            code = ensureLeadCode(lead);
        }
        if (String.isBlank(code)) {
            code = buildCode(opportunityId);
        }

        try {
            update new Opportunity(Id = opportunityId, Codigo_no_Parceiro__c = code);
        } catch (Exception ex) {
            safeLog('ensureOpportunityCode', 'Nao foi possivel persistir codigo do totem na Oportunidade.');
        }
        return code;
    }

    private static String ensureLeadCode(Lead lead) {
        if (lead == null || lead.Id == null) {
            return null;
        }

        String currentCode = (String) lead.get('Codigo_no_Parceiro__c');
        if (!String.isBlank(currentCode)) {
            return currentCode;
        }

        String code = buildCode(lead.Id);
        try {
            update new Lead(Id = lead.Id, Codigo_no_Parceiro__c = code);
        } catch (Exception ex) {
            safeLog('ensureLeadCode', 'Nao foi possivel persistir codigo do totem no Lead.');
        }
        return code;
    }

    private static String resolveCodeForLead(Id leadId, Id opportunityId) {
        if (opportunityId != null) {
            return ensureOpportunityCode(opportunityId, leadId);
        }
        if (leadId != null) {
            Lead lead = TotemOportunidadesSelector.getLeadCode(leadId);
            if (lead != null) {
                return ensureLeadCode(lead);
            }
        }
        return null;
    }

    private static String buildCode(Id recordId) {
        String id15 = String.valueOf(recordId).substring(0, 15);
        return 'VEO-' + id15.right(5).toUpperCase();
    }

    private static void markValidatedByCode(Id leadId, Id opportunityId) {
        try {
            String value = 'Validado por codigo no totem oportunidades';
            if (leadId != null) {
                update new Lead(Id = leadId, Status_Validacao_Lead__c = value);
            }
            if (opportunityId != null) {
                update new Opportunity(Id = opportunityId, Status_Validacao_Lead__c = value);
            }
        } catch (Exception ex) {
            safeLog('markValidatedByCode', 'Nao foi possivel marcar validacao por codigo.');
        }
    }

    private static Set<String> buildCodeCandidates(String value) {
        Set<String> candidates = new Set<String>();
        if (String.isBlank(value)) {
            return candidates;
        }
        String trimmed = value.trim();
        String normalized = normalizeCode(trimmed);
        candidates.add(trimmed);
        candidates.add(trimmed.toUpperCase());
        candidates.add(normalized);
        if (normalized.startsWith('VEO') && normalized.length() > 3) {
            candidates.add('VEO-' + normalized.substring(3));
        }
        return candidates;
    }

    private static String normalizeCode(String value) {
        return String.isBlank(value) ? null : value.trim().replaceAll('[^A-Za-z0-9]', '').toUpperCase();
    }

    private static String normalizePhoneComparable(String value) {
        String digits = onlyDigits(value);
        if (String.isBlank(digits)) {
            return null;
        }
        if (digits.startsWith('55') && digits.length() > 11) {
            digits = digits.substring(2);
        }
        return digits;
    }

    private static String onlyDigits(String value) {
        return String.isBlank(value) ? null : value.replaceAll('[^0-9]', '');
    }

    private static String normalizeEmail(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    private static String normalizeText(String value, String fallback, Integer maxLength) {
        String source = String.isBlank(value) ? fallback : value.trim();
        if (String.isBlank(source)) {
            return null;
        }
        source = source.replaceAll('\\s+', ' ');
        return source.length() > maxLength ? source.substring(0, maxLength) : source;
    }

    private static Integer normalizeValidityDays(Integer value) {
        if (value == null || value <= 0) {
            return DEFAULT_CODE_VALIDITY_DAYS;
        }
        return Math.min(value, 365);
    }

    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<String, String> splitName(String nomeCompleto) {
        Map<String, String> result = new Map<String, String>{
            'firstName' => '',
            'lastName' => 'Cliente'
        };
        if (String.isBlank(nomeCompleto)) {
            return result;
        }

        List<String> parts = nomeCompleto.trim().replaceAll('\\s+', ' ').split(' ');
        if (parts.isEmpty()) {
            return result;
        }

        result.put('lastName', parts[parts.size() - 1]);
        if (parts.size() > 1) {
            List<String> firstParts = new List<String>();
            for (Integer i = 0; i < parts.size() - 1; i++) {
                firstParts.add(parts[i]);
            }
            result.put('firstName', String.join(firstParts, ' '));
        }
        return result;
    }

    private static String maskName(String value) {
        if (String.isBlank(value)) {
            return 'Cliente';
        }
        List<String> parts = value.trim().split(' ');
        String first = parts[0];
        String lastInitial = parts.size() > 1 ? parts[parts.size() - 1].left(1).toUpperCase() + '.' : '';
        return String.isBlank(lastInitial) ? first : first + ' ' + lastInitial;
    }

    private static String maskEmail(String value) {
        String email = normalizeEmail(value);
        if (String.isBlank(email) || !email.contains('@')) {
            return null;
        }
        List<String> pieces = email.split('@');
        String local = pieces[0];
        String domain = pieces.size() > 1 ? pieces[1] : '';
        return local.left(1) + '***@' + domain;
    }

    private static String maskPhone(String value) {
        String digits = normalizePhoneComparable(value);
        if (String.isBlank(digits)) {
            return null;
        }
        return '***' + digits.right(Math.min(4, digits.length()));
    }

    private static void safeLog(String methodName, String message) {
        try {
            new Logger()
                .setClass('TotemOportunidadesController')
                .setCategory('totem-oportunidades')
                .setMethod(methodName)
                .setLog(message)
                .createWarn();
        } catch (Exception ignored) {
            System.debug(LoggingLevel.WARN, message);
        }
    }
}