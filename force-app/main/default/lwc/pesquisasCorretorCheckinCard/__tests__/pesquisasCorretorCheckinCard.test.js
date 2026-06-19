import { createElement } from "@lwc/engine-dom";
import PesquisasCorretorCheckinCard from "c/pesquisasCorretorCheckinCard";
import obterLojaPadrao from "@salesforce/apex/PesquisasPortalController.obterLojaPadrao";

jest.mock(
  "@salesforce/apex/PesquisasPortalController.obterLojaPadrao",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock("@salesforce/community/basePath", () => "/pesquisas", {
  virtual: true
});

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-pesquisas-corretor-checkin-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("exibe loja padrão e usa a mesma URL no CTA e no QR Code", async () => {
    obterLojaPadrao.mockResolvedValue({
      codigo: "LOJA-MORUMBI",
      nome: "Loja Morumbi",
      endereco: "Av. Giovanni Gronchi, 2967",
      padrao: true
    });
    const element = createElement("c-pesquisas-corretor-checkin-card", {
      is: PesquisasCorretorCheckinCard
    });
    document.body.appendChild(element);

    await flushPromises();
    await flushPromises();

    const link = element.shadowRoot.querySelector(".cta");
    const qrCode = element.shadowRoot.querySelector("c-pesquisas-qr-code");
    expect(element.shadowRoot.textContent).toContain("Loja Morumbi");
    expect(link.getAttribute("href")).toBe(
      "/pesquisas/checkin-corretor?loja=LOJA-MORUMBI"
    );
    expect(qrCode.value).toBe(
      `${window.location.origin}/pesquisas/checkin-corretor?loja=LOJA-MORUMBI`
    );
  });

  it("mostra erro seguro quando a loja padrão não carrega", async () => {
    obterLojaPadrao.mockRejectedValue({
      body: { message: "Não foi possível carregar a loja padrão." }
    });
    const element = createElement("c-pesquisas-corretor-checkin-card", {
      is: PesquisasCorretorCheckinCard
    });
    document.body.appendChild(element);

    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
  });
});
