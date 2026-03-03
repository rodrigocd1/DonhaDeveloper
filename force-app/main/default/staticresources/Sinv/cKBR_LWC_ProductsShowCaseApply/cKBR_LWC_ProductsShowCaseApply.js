import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlexCardMixin } from 'omnistudio/flexCardMixin';
import { getDataHandler } from 'omnistudio/utility';
import percentualCDI from "@salesforce/label/c.CKBR_CL_PercentualCDI";
import horarioMovimentacao from "@salesforce/label/c.CKBR_CL_Horario_Movimentacao";
import horarioBR from "@salesforce/label/c.CKBR_CL_Horario"; 
import diasCarencia from "@salesforce/label/c.CKBR_Msg_DiasCarencia";
import getToastMessage from '@salesforce/apex/CKBR_CTL_ProductShowCaseApply.getParametrizacoesSinv';


export default class TelaPocRendaAltaAplicar extends FlexCardMixin(LightningElement) {
    @api isShowAplicar;
    @api investmentSelected;
    @api vitrineApiList;

    @track isShowConfirm;

    @track spinnerTable = false;
    @track isHorarioAbertura = false;
    @track horarioAbertura = '';
    @track horarioFechamento = '';
    @track valorAplicacao = ''; 
    @track isApplyDisabled = true; 
    @track isDisabled = true;
    @track valorPercentual; 
    @track valorTaxaNegociada = '';
    @track valorPrazo = '';
    @track valueLiquidez = '';
    @track valorPrazoDiasUteis = '';
    @track valorVencimentoAplicacao = '';
    @track valorVencimentoCarencia = '';
    @track valueDiasCarencia = 370;
    @track valorResgateMinimo = 100;
    @track valorDataInvestimento = '';
    @track cdiNegociado = '';
    @track taxa252Cliente = '';
    @track taxa360Cliente = '';
    @track custoBanco = '';
    @track taxa252Banco = '';
    @track taxa360Banco = '';
    @track spreadBanco = '';
    @track resultadoFinanceiroBanco = '';
    @track valorPrazoDiasCorridos = '';
    @track horarioMovimentacao = '';
    @track isDisabledPercentualCDI = false; 
    @track isDisabledvalorPrazoDiasCorridos = false; 
    @track isDisabledvalorVencimentoAplicacao = false;
    @track isDisabledValorResgateMinimo = false; 
    @track isDisabledCdiNegociado = false; 
    @track isDisabledCustoBanco = false; 
    @track isDisabledTaxa252Cliente = false; 
    @track isDisabledTaxa360Cliente = false; 
    @track isDisabledTaxa252Banco = false; 
    @track isDisabledTaxa360Banco = false; 
    @track isDisabledSpreadBanco = false; 
    @track isDisabledResultadoFinanceiro = false;  
    @track isShowConfirm = false; 
    @track selectedConfirmar = ''; 
    @track errorTrack = ''; 

    
    label = {
        percentualCDI, 
        horarioMovimentacao,
        horarioBR,
        diasCarencia
    }

    connectedCallback() {
        this.isHorarioAbertura = !!this.investmentSelected?.horarioAbertura;
        this.horarioMovimentacao = this.investmentSelected.horarioMovimentacao || '';
        this.horarioFechamento = this.investmentSelected?.horarioFechamento || '';
        this.nome = this.investmentSelected?.nome || '';  
        this.horarioMovimentacao = this.investmentSelected?.horarioMovimentacao || '08h00 às 16h30';
        this.classificacaoTributaria = this.investmentSelected?.classeAtivoDescricao || '';

        // Inicializar valores de datas com o formato ISO 8601, garantindo que todas as variáveis tenham valores válidos
        this.valorDataInvestimento = new Date().toISOString().slice(0, 10);
        this.valorVencimentoAplicacao = this.calculateVencimentoAplicacao() || '';
        this.valorVencimentoCarencia = this.calculateVencimentoCarencia() || '';
    }  

    holidaysFixed = [
        { month: 1, day: 1 },    // Confraternização Universal
        { month: 4, day: 21 },   // Tiradentes
        { month: 5, day: 1 },    // Dia do Trabalhador
        { month: 9, day: 7 },    // Independência do Brasil
        { month: 10, day: 12 },  // Nossa Senhora Aparecida
        { month: 11, day: 2 },   // Finados
        { month: 11, day: 15 },  // Proclamação da República
        { month: 12, day: 25 }   // Natal
    ];

    calculateEaster(year) {
        let a = year % 19;
        let b = Math.floor(year / 100);
        let c = year % 100;
        let d = Math.floor(b / 4);
        let e = b % 4;
        let f = Math.floor((b + 8) / 25);
        let g = Math.floor((b - f + 1) / 3);
        let h = (19 * a + b - d - g + 15) % 30;
        let i = Math.floor(c / 4);
        let k = c % 4;
        let l = (32 + 2 * e + 2 * i - h - k) % 7;
        let m = Math.floor((a + 11 * h + 22 * l) / 451);
        let month = Math.floor((h + l - 7 * m + 114) / 31);
        let day = ((h + l - 7 * m + 114) % 31) + 1;
        return new Date(year, month - 1, day);
    }

    calculateMobileHolidays(year) {
        let easter = this.calculateEaster(year);
        return [
            new Date(easter.getTime() - 47 * 24 * 60 * 60 * 1000), // Carnaval
            new Date(easter.getTime() - 2 * 24 * 60 * 60 * 1000),  // Sexta-feira Santa
            new Date(easter.getTime() + 60 * 24 * 60 * 60 * 1000)  // Corpus Christi
        ];
    }

    calculateAllHolidays(year) {
        let holidays = this.holidaysFixed.map(h => new Date(year, h.month - 1, h.day));
        holidays = holidays.concat(this.calculateMobileHolidays(year));
        return holidays;
    }

    handlePrazoDiasCorridos(event) { 
        this.valorPrazoDiasCorridos = event.target.value;
    
        if (this.valorPrazoDiasCorridos) {
            const startDate = new Date();
            // Calcula a data de vencimento com base nos dias corridos digitados
            this.valorVencimentoAplicacao = this.calculateVencimentoAplicacao(parseInt(this.valorPrazoDiasCorridos));
            // Calcula os dias úteis a partir da data inicial até a data de vencimento
            this.valorPrazoDiasUteis = this.calculateBusinessDays(startDate, parseInt(this.valorPrazoDiasCorridos));
            this.checkApplyEnabled(); 
        } else {
            this.valorPrazoDiasUteis = '';
            this.valorVencimentoAplicacao = '';
            this.checkApplyEnabled();
        }
    }
    
    calculateBusinessDays(startDate, prazoDiasCorridos) {
        let holidays = this.calculateAllHolidays(startDate.getFullYear());
        let currentDate = new Date(startDate);
        let businessDays = 0;
        let totalDays = 0;
    
        while (totalDays < prazoDiasCorridos) {
            currentDate.setDate(currentDate.getDate() + 1);
            totalDays++;
            if (currentDate.getDay() !== 0 && currentDate.getDay() !== 6 && !holidays.some(holiday => holiday.getTime() === currentDate.getTime())) {
                businessDays++;
            }
        }
        
        return businessDays;
    } 
    

    calculateVencimentoAplicacao(prazoDiasCorridos = 0) {
        if (prazoDiasCorridos > 0) {
            let vencimentoDate = new Date();
            vencimentoDate.setDate(vencimentoDate.getDate() + prazoDiasCorridos);
            return vencimentoDate.toISOString().slice(0, 10);
        }
        return '';
    }

    calculateVencimentoCarencia() { 
        if (this.valueDiasCarencia) {
            let vencimentoDate = new Date();
            vencimentoDate.setDate(vencimentoDate.getDate() + parseInt(this.valueDiasCarencia));
            return vencimentoDate.toISOString().slice(0, 10);
        }
        return null;
    }

    get formattedValorAplicacao() {
        return this.formatCurrency(this.valorAplicacao);
    }

    get formattedValorResgateMinimo() {
        return this.formatCurrency(this.valorResgateMinimo);
    }

    get formattedPercentualCDI() {
        return this.formatPercent(this.valorPercentual);
    }

    get formattedCdiNegociado() {
        return this.formatPercent(this.cdiNegociado);
    }

    get formattedCustoBanco() {
        return this.formatPercent(this.custoBanco);
    }

    get formattedTaxa252Cliente() {
        return this.formatPercent(this.taxa252Cliente);
    }

    get formattedTaxa360Cliente() {
        return this.formatPercent(this.taxa360Cliente);
    }

    get formattedTaxa252Banco() {
        return this.formatPercent(this.taxa252Banco);
    }

    get formattedTaxa360Banco() {
        return this.formatPercent(this.taxa360Banco);
    }

    get formattedSpreadBanco() {
        return this.spreadBanco;
    }

    get formattedResultadoFinanceiro() {
        return this.formatCurrency(this.resultadoFinanceiroBanco);
    }

    formatCurrency(value) {
        if (!value) return '';
        return new Intl.NumberFormat('pt-BR', {
            style: 'currency',
            currency: 'BRL'
        }).format(value);
    }

    formatPercent(value) {
        if (!value) return '';
        return `${parseFloat(value).toFixed(2)}%`;   
    }

    handleChangeTaxa252Banco(event) {
        this.taxa252Banco = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeTaxa360Banco(event) {
        this.taxa360Banco = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    

    handleChangeValorAplicacao(event) {
        try {
            this.valorAplicacao = event.target.value.replace(/[^\d,]/g, '');
            this.isDisabled = this.valorAplicacao ? false : true;
    
            if (this.valorAplicacao) {
                const valorAplicacaoNumerico = parseFloat(this.valorAplicacao.replace(',', '.'));
                if (isNaN(valorAplicacaoNumerico)) {
                    throw new Error('Valor da aplicação inválido.');
                }
    
                this.valorVencimentoCarencia = this.calculateVencimentoCarencia();
                this.valorPercentual = 910;
                this.valueLiquidez = 'Diária';
                this.valueDiasCarencia = this.label.diasCarencia;  
    
                this.isDisabledPercentualCDI = true;
                this.isDisabledValorResgateMinimo = true;  
            } else {
                this.isDisabledPercentualCDI = false;
                this.isDisabledValorResgateMinimo = false;
            }
    
            this.checkApplyEnabled();
        } catch (error) {    
            this.errorTrack = error; 
            this.checkApplyEnabled(); 
        }
    }
    
    

    

    handleChangePercentual(event) {
        this.valorPercentual = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeResgateMinimo(event) {
        this.valorResgateMinimo = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeCdiNegociado(event) {
        this.cdiNegociado = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeCustoBanco(event) {
        this.custoBanco = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeTaxa252Cliente(event) {
        this.taxa252Cliente = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeTaxa360Cliente(event) {
        this.taxa360Cliente = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeSpreadBanco(event) {
        this.spreadBanco = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeResultadoFinanceiro(event) {
        this.resultadoFinanceiroBanco = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeLiquidez(event) {
        this.valueLiquidez = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleChangeDiasCarencia(event) {
        this.valueDiasCarencia = event.target.value.replace(/[^\d,]/g, '');
        this.checkApplyEnabled();
    }

    handleVencimentoCarencia(event) {
        this.valorVencimentoCarencia = event.target.value;
        this.checkApplyEnabled();
    }

    handleChangePrazoDiasUteis(event) {
        this.valorPrazoDiasUteis = event.target.value;
        this.checkApplyEnabled();
    }

    handleChangeDataInvestimento(event) {
        this.valorDataInvestimento = event.target.value;
        this.checkApplyEnabled(); 
    }
 
    checkApplyEnabled() {  
        console.log('entrou no checkApplyEnabled 1'); 
        let isValorAplicacaoValid = this.valorAplicacao && this.valorAplicacao != '';
        let isPercentualCDIValid = this.valorPercentual && this.valorPercentual != '';
        let isPrazoDiasCorridosValid = this.valorPrazoDiasCorridos && this.valorPrazoDiasCorridos != ''; 
        let isVencimentoAplicacaoValid = this.valorVencimentoAplicacao && this.valorVencimentoAplicacao != '';
        console.log('entrou no checkApplyEnabled 2');  
        // Verifica se todos os campos obrigatórios estão preenchidos
        //console.log('isValorAplicacaoValid >>> ' + isValorAplicacaoValid); 
        //console.log('isPrazoDiasCorridosValid >>> ' + isPrazoDiasCorridosValid); 
        //console.log('isVencimentoAplicacaoValid >>> ' + isVencimentoAplicacaoValid);  
        this.isApplyDisabled = !(isValorAplicacaoValid && isPercentualCDIValid && isPrazoDiasCorridosValid && isVencimentoAplicacaoValid);
        console.log('this.isApplyDisabled >>>> ' + this.isApplyDisabled); 
    } 
    

    isDisabledFieldsValorAplicacao(){ 
        if(this.valorAplicacao != undefined || this.valorAplicacao != ''){
            this.isDisabledPercentualCDI = true; 
            this.isDisabledValorResgateMinimo = true; 
            this.isDisabledCdiNegociado = true; 
            this.isDisabledCustoBanco = true; 
            this.isDisabledTaxa252Cliente = true; 
            this.isDisabledTaxa360Cliente = true; 
            this.isDisabledTaxa252Banco = true; 
            this.isDisabledTaxa360Banco = true;   
            this.isDisabledSpreadBanco = true; 
            this.isDisabledResultadoFinanceiro = true; 
        }else{
            this.isDisabledPercentualCDI = false; 
            this.isDisabledValorResgateMinimo = false; 
            this.isDisabledCdiNegociado = false; 
            this.isDisabledCustoBanco = false; 
            this.isDisabledTaxa252Cliente = false; 
            this.isDisabledTaxa360Cliente = false; 
            this.isDisabledTaxa252Banco = false; 
            this.isDisabledTaxa360Banco = false;   
            this.isDisabledSpreadBanco = false; 
            this.isDisabledResultadoFinanceiro = false; 
        }
    }


    handleOpenEdit(event){   
        this.isShowConfirm = event.detail.isShowConfirm;   
    }

    handleCloseConfirm(event){ 
        this.isShowConfirm = event.detail.isShowConfirm;
        this.closeApply(event);    
    }

    closeApply() {
        this.isShowAplicar = false;
        const selectedEvent = new CustomEvent('selected', {
            detail: this.isShowAplicar
        });
        this.dispatchEvent(selectedEvent);
    }

    finishedApplication(event) {   
        // Validar os campos obrigatórios
        const isValorAplicacaoValid = this.valorAplicacao && this.valorAplicacao !== '';
        const isValorPercentualValid = this.valorPercentual && this.valorPercentual !== '';
        const isPrazoDiasCorridosValid = this.valorPrazoDiasCorridos && this.valorPrazoDiasCorridos !== '';
        const isVencimentoAplicacaoValid = this.valorVencimentoAplicacao && this.valorVencimentoAplicacao !== '';
    
        // Verificar se todos os campos obrigatórios estão preenchidos
        if (!isValorAplicacaoValid || !isValorPercentualValid || !isPrazoDiasCorridosValid || !isVencimentoAplicacaoValid) {
            this.showToastMessage('Erro', 'Preencha todos os campos obrigatórios.', 'error');
            getToastMessage({ aMessageType: this.messageType }) 
        .then(element => { 
            if (element) {  
                // Exibe a mensagem de showToast com os dados retornados
                element.forEach(result => { 
                if(result.DeveloperName == 'errorProductShowCaseApply'){ 
                    this.showToastMessage(result.CKBR_CMT_TXT_ErrorMessage__c, result.CKBR_CMT_TXT_InfoMessage__c, result.Label);
                }
            });
            }     

        }).catch(error => {
            // Lidar com erros de chamada ao Apex
            console.error('Error fetching toast message: ', error);
            getToastMessage({ aMessageType: this.messageType }) 
            .then(result => {
                if(result.DeveloperName == 'errorProductShowConfirm'){ 
                    this.showToastMessage(result.CKBR_CMT_TXT_ErrorMessage__c, result.CKBR_CMT_TXT_InfoMessage__c, result.Label);
                } 
        });
            
        }); 
            return;    
        }
    
        // Lógica para preencher o objeto selectedConfirmar
        this.selectedConfirmar = {   
            idRegistro : this.investmentSelected.financialAccountId,
            classificacaoTributaria: this.investmentSelected?.classeAtivoDescricao || '',
            circleStyle: this.investmentSelected?.circleStyle,
            valueaplicacao: this.formattedValorAplicacao || '',
            valuePercentual: this.formattedPercentualCDI || '',
            valueVencimentoAplicacao: this.valorVencimentoAplicacao || '',
            valueVencimentoCarencia: this.valorVencimentoCarencia || '',
            valueDiasCarencia: this.valueDiasCarencia || '',
            valuePrazoDiasCorridos: this.valorPrazoDiasCorridos || '',
            valuePrazoDiasUteis: this.valorPrazoDiasUteis || '',
            valueDataInvestimento: this.valorDataInvestimento || '', 
            valueCustoBanco: this.formattedCustoBanco || '',
            valueTaxa252Cliente: this.formattedTaxa252Cliente || '',
            valueTaxa360Cliente: this.formattedTaxa360Cliente || '',
            valueTaxa252Banco : this.formattedTaxa252Banco || '',
            valueTaxa360Banco : this.formattedTaxa360Banco || '',
            valueSpreadBanco : this.formattedSpreadBanco || '',
            valueResultadoFinanceiro : this.formattedResultadoFinanceiro || '',
            valueCDINegociado : this.formattedCdiNegociado || '',  
        };
    
        this.isShowConfirm = true;
    }
    
    //Esta função seria no componente de Confirmar. 
    getOmniStudioVIPFinished() {
        this.spinnerTable = true;
        let optionsMap = {     
            "aRecordId" : this.investmentSelected.financialAccountId,
            "vitrineApiList" : this.vitrineApiList,   
            "aInvestmentSelected" : this.investmentSelected,
            "selectedConfirmar" : this.selectedConfirmar
        }      
        let vipRes = JSON.stringify({ 
            type: 'integrationprocedure',
            value: {
                ipMethod: 'CKBR_VitrineProdutoAplicarRendaFixa',  
                inputMap: JSON.stringify(optionsMap), 
            },
        });
        getDataHandler(vipRes).then((data) => { 
            this.isShowAplicar = false;
            const selectedEvent = new CustomEvent('selected', {
                detail: this.isShowAplicar
            });
            this.dispatchEvent(selectedEvent);
            this.showToastMessage('Sucesso', 'Aplicação Financeira realizada com sucesso', 'success');
            setTimeout(() => {
                this.spinnerTable = false;
            }, 2000);
        }).catch((error) => {
            console.error('Error fetching data', error);
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }


    handleTabFromValorAplicacao(event) {
        try {
            if (event.key === 'Tab' && !event.shiftKey) {
                event.preventDefault();
                const prazoDiasCorridosField = this.template.querySelector('[data-id="prazoDiasCorridos"]');
                if (prazoDiasCorridosField) {
                    prazoDiasCorridosField.focus();
                } else {
                    throw new Error('Campo "Prazo (Dias Corridos)" não encontrado.');
                }
            }
        } catch (error) {
            console.error('Erro na navegação com Tab:', error);
        }
    }
    
    
    handleTabFromPrazoDiasCorridos(event) {
        try {  
            if (event.key === 'Tab' && !event.shiftKey) {
                event.preventDefault();
                const vencimentoAplicacaoField = this.template.querySelector('[data-id="vencimentoAplicacao"]');
                if (vencimentoAplicacaoField) {
                    vencimentoAplicacaoField.focus();
                } else {
                    throw new Error('Campo "Vencimento da Aplicação" não encontrado.');
                }
            }
        } catch (error) {
            console.error('Erro na navegação com Tab:', error);
        }
    }
    
    
    
    
    



    handleVencimentoAplicacaoChange(event) {
        this.valorVencimentoAplicacao = event.target.value;
        const prazoDiasCorridos = this.calculatePrazoDiasCorridos(new Date(), new Date(this.valorVencimentoAplicacao));
        this.valorPrazoDiasCorridos = prazoDiasCorridos;
        this.valorPrazoDiasUteis = this.calculateBusinessDays(new Date(), prazoDiasCorridos);
        this.checkApplyEnabled();  
    }  
    


    calculatePrazoDiasCorridos(startDate, endDate) {
        const diffTime = Math.abs(endDate - startDate);
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        return diffDays;
    }
    
    
    


    handleClickConsultar(event){

        if(this.valorAplicacao){
            let valorAplicacaoNumerico = parseFloat(this.valorAplicacao.replace(/[^\d,]/g, '').replace(',', '.'));

        // Exemplos de cálculos  
        this.cdiNegociado = (valorAplicacaoNumerico * 0.05).toFixed(2); 
        this.custoBanco = (valorAplicacaoNumerico * 0.01).toFixed(2);   
        this.taxa252Cliente = (valorAplicacaoNumerico * 0.03).toFixed(2);
        this.taxa360Cliente = (valorAplicacaoNumerico * 0.035).toFixed(2); 
        this.taxa252Banco = (valorAplicacaoNumerico * 0.015).toFixed(2);  
        this.taxa360Banco = (valorAplicacaoNumerico * 0.018).toFixed(2);  
        this.spreadBanco = (valorAplicacaoNumerico * 0.02).toFixed(2);    
        this.resultadoFinanceiroBanco = (valorAplicacaoNumerico * 0.045).toFixed(2); 
    
        
            this.isDisabledFieldsValorAplicacao();    
            this.spinnerTable = true; 
        }
        
            //this.getVIPAplicar();
    }

    getVIPAplicar(){

        let optionsMap = {    
            "aRecordId" : this.investmentSelected.financialAccountId,
            "vitrineApiList" : this.vitrineApiList,    
            "aInvestmentSelected" : this.investmentSelected
        }   
        let vipRes = JSON.stringify({  
            type: 'integrationprocedure',
            value: {
                ipMethod: 'CKBR_ProdutoInfoAplicacao',   
                inputMap: JSON.stringify(optionsMap), 
            },
        });
        getDataHandler(vipRes).then((data) => {
            
            setTimeout(() => {
                this.spinnerTable = false;
            }, 2000);
        }).catch((error) => {
            console.error('Error fetching data', error);
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }

    showToastMessage(titleMsg, messageMsg, variantMsg) {
        const evt = new ShowToastEvent({
            title: titleMsg,
            message: messageMsg,
            variant: variantMsg,
        });
        this.dispatchEvent(evt);
    }

    closeApply(event) {
        this.isShowAplicar = false;
        const selectedEvent = new CustomEvent("closeapply", { detail: this.isShowAplicar });
        this.dispatchEvent(selectedEvent);
    }

    handleApply(event) { 
        // This function would trigger the application logic
        this.finishedApplication(event); 
    }

    hasErrorClass(value) {
        return value === '' ? 'hasError' : '';
    }

    get isValorAplicacaoEmpty() {
        return this.valorAplicacao === '';
    }

    get isPrazoDiasCorridosEmpty() {
        return this.valorPrazoDiasCorridos === '';
    }

    get isVencimentoAplicacaoEmpty() { 
        return this.valorVencimentoAplicacao === '';
    }
}