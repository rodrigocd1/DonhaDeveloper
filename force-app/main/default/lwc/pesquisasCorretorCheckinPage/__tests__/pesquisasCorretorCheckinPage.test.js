import { createElement } from "@lwc/engine-dom";
import PesquisasCorretorCheckinPage from "c/pesquisasCorretorCheckinPage";
import obterLojaPadrao from "@salesforce/apex/PesquisasPortalController.obterLojaPadrao";
import listarLojasAtivas from "@salesforce/apex/PesquisasPortalController.listarLojasAtivas";
import confirmarCheckinCorretor from "@salesforce/apex/PesquisasPortalController.confirmarCheckinCorretor";

jest.mock(
  "@salesforce/apex/PesquisasPortalController.obterLojaPadrao",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PesquisasPortalController.listarLojasAtivas",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PesquisasPortalController.confirmarCheckinCorretor",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const stores = [
  {
    codigo: "LOJA-MORUMBI",
    nome: "Loja Morumbi",
    endereco: "Av. Giovanni Gronchi, 2967",
    padrao: true
  },
  {
    codigo: "LOJA-TATUAPE",
    nome: "Loja Tatuapé",
    endereco: "Rua Tuiuti, 2147",
    padrao: false
  }
];
const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-pesquisas-corretor-checkin-page", () => {
  beforeEach(() => {
    obterLojaPadrao.mockResolvedValue(stores[0]);
    listarLojasAtivas.mockResolvedValue(stores);
    window.history.replaceState(
      {},
      "",
      "/pesquisas/checkin-corretor?loja=LOJA-MORUMBI"
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("carrega a loja da URL e permite trocar a seleção", async () => {
    const element = createElement("c-pesquisas-corretor-checkin-page", {
      is: PesquisasCorretorCheckinPage
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Loja Morumbi");
    element.shadowRoot.querySelector(".change-store").click();
    await flushPromises();
    const selector = element.shadowRoot.querySelector("lightning-combobox");
    selector.dispatchEvent(
      new CustomEvent("change", { detail: { value: "LOJA-TATUAPE" } })
    );
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Loja Tatuapé");
    expect(window.location.search).toBe("?loja=LOJA-TATUAPE");
  });

  it("usa loja padrão e avisa quando o código da URL é inválido", async () => {
    window.history.replaceState(
      {},
      "",
      "/pesquisas/checkin-corretor?loja=INEXISTENTE"
    );
    const element = createElement("c-pesquisas-corretor-checkin-page", {
      is: PesquisasCorretorCheckinPage
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Loja Morumbi");
    expect(element.shadowRoot.querySelector('[role="status"]')).not.toBeNull();
  });

  it("normaliza o CPF e confirma o check-in uma única vez", async () => {
    confirmarCheckinCorretor.mockResolvedValue({
      sucesso: true,
      mensagem: "Check-in confirmado com sucesso."
    });
    const element = createElement("c-pesquisas-corretor-checkin-page", {
      is: PesquisasCorretorCheckinPage
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    const cpfInput = element.shadowRoot.querySelector(".cpf-input");
    cpfInput.setCustomValidity = jest.fn();
    cpfInput.reportValidity = jest.fn(() => true);
    cpfInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "52998224725" } })
    );
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flushPromises();
    await flushPromises();

    expect(confirmarCheckinCorretor).toHaveBeenCalledTimes(1);
    expect(confirmarCheckinCorretor).toHaveBeenCalledWith({
      input: {
        cpf: "529.982.247-25",
        codigoLoja: "LOJA-MORUMBI",
        honeypot: ""
      }
    });
    expect(element.shadowRoot.textContent).toContain(
      "Check-in confirmado com sucesso."
    );
  });
});
