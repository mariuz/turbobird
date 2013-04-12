unit Update;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs,
  StdCtrls, Buttons, ExtCtrls, httpsend, Process;

const
  {$IFDEF LINUX}
   Target = 'Linux';
  {$ENDIF}

  {$IFDEF WINDOWS}
   Target = 'Win';
  {$ENDIF}

  {$IFDEF MAC}
   Target = 'Mac';
  {$ENDIF}

  {$IFDEF BSD}
   Target = 'BSD';
  {$ENDIF}

  {$ifDEF CPU32}
   Arch = '32';
  {$ENDIF}

  {$ifDEF CPU64}
   Arch = '64';
  {$ENDIF}

type


  { THTTPDownload }

  THTTPDownload = class(TThread)
    private
      fURL: string;
      fFileName: string;
      fSuccess: Boolean;
      fErrorMessage: string;
    public
      constructor Create(URL, FileName: string);
      procedure Execute; override;
  end;


  { TfmUpdate }
  TfmUpdate = class(TForm)
    bbSearch: TBitBtn;
    bbDownload: TBitBtn;
    cxProxy: TCheckBox;
    edProxy: TEdit;
    edPort: TEdit;
    edUser: TEdit;
    edPassword: TEdit;
    GroupBox1: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    laTime: TLabel;
    Process1: TProcess;
    stStatus: TStaticText;
    stVersion: TStaticText;
    stNewVersion: TStaticText;
    Timer1: TTimer;
    procedure bbDownloadClick(Sender: TObject);
    procedure bbSearchClick(Sender: TObject);
    procedure cxProxyChange(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure Timer1Timer(Sender: TObject);
  private
    fNewFileName: string;
    downloadThread: THTTPDownload;
    { private declarations }
    procedure DownloadTerminated(Sender: TObject);
  public
    Major, Minor, ReleaseVersion: Word;
    Started: TDateTime;
    function GetNewVersion(var AFileName, Version, ResMsg: string; var NewVersion: Boolean): Boolean;
    function DownloadNewVersion: Boolean;
    procedure Init(aMajor, aMinor, aReleaseVersion: Word);
    { public declarations }
  end;

var
  fmUpdate: TfmUpdate;

implementation

uses Main;
{ TfmUpdate }


{ THTTPDownload }

constructor THTTPDownload.Create(URL, FileName: string);
begin
  inherited Create(True);
  fURL:= URL;
  fFileName:= FileName;
end;

procedure THTTPDownload.Execute;
var
  http: THTTPSend;
  List: TStringList;
begin
  try
    http:= THTTPSend.Create;

    with fmUpdate do
    if cxProxy.Checked then
    begin
      http.ProxyHost:= edProxy.Text;
      http.ProxyPort:= edPort.Text;
      http.ProxyUser:= edUser.Text;
      http.ProxyPass:= edPassword.Text;
    end;

    fSuccess:= http.HTTPMethod('GET', fURL);
    if fSuccess then
    if http.Document.Size > 10000 then  // Actual file has been downloaded
      http.Document.SaveToFile(ExtractFilePath(ParamStr(0)) + fFileName)
    else
    begin // Error HTML response
      List:= TStringList.Create;
      List.LoadFromStream(http.Document);
      fSuccess:= False;
      fErrorMessage:= List.Text;
      List.Free;
    end;

    http.Free

  except
  on e: exception do
  begin
    fSuccess:= False;
    fErrorMessage:= e.Message;
  end;
  end;

end;

procedure TfmUpdate.bbSearchClick(Sender: TObject);
var
  Version: string;
  ResMsg: string;
  ThereIsaNewVersion: Boolean;
begin
  if GetNewVersion(fNewFileName, Version, ResMsg, ThereisaNewVersion) then
  begin
    if ThereisaNewVersion then
    begin
      stNewVersion.Caption:= Version;
      stNewVersion.Font.Color:= clGreen;
      stNewVersion.Font.Style:= [fsBold];
      bbDownload.Visible:= True;
    end
    else
    begin
      stNewVersion.Caption:= 'There is no new version';
      stNewVersion.Font.Color:= clBlue;
      bbDownload.Visible:= False;
    end;
  end
  else
  if pos('not found', LowerCase(ResMsg)) > 0 then
  begin
    stNewVersion.Caption:= 'Error while fetching new version';
    stNewVersion.Font.Color:= clMaroon;
    bbDownload.Visible:= False;
  end
  else
    ShowMessage('Internet connection error');

end;

procedure TfmUpdate.bbDownloadClick(Sender: TObject);
begin
  stStatus.Caption:= 'Downloading.. please wait';
  bbDownload.Enabled:= False;
  bbSearch.Enabled:= False;
  cxProxy.Enabled:= False;
  laTime.Visible:= True;
  Started:= Now;
  Timer1.Enabled:= True;
  DownloadNewVersion;
end;

procedure TfmUpdate.cxProxyChange(Sender: TObject);
begin
  GroupBox1.Visible:= cxProxy.Checked;
end;

procedure TfmUpdate.FormActivate(Sender: TObject);
begin
  stVersion.Caption:= Format('%d.%d.%d', [Major, Minor, ReleaseVersion]);
end;

procedure TfmUpdate.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction:= caFree;
end;

procedure TfmUpdate.Timer1Timer(Sender: TObject);
begin
  laTime.Caption:= FormatDateTime('nn:ss', Now - Started);
end;

procedure TfmUpdate.DownloadTerminated(Sender: TObject);
var
  AppName: string;
  ResMsg: string;
begin
  {$IFDEF LINUX}
  AppName:= 'CodeUpdater';
  {$ENDIF}

  {$IFDEF MSWINDOWS}
  AppName:= 'CodeUpdater.exe';
  {$ENDIF}
  bbDownload.Enabled:= True;
  bbSearch.Enabled:= True;
  cxProxy.Enabled:= True;
  ResMsg:= downloadThread.fErrorMessage;

  if downloadThread.fSuccess then
  begin
    stStatus.Caption:= 'Update completed';
    SetCurrentDir(ExtractFileDir(ParamStr(0)));
    Process1.CommandLine:= AppName + ' ' + fNewFileName + ' ' + ExtractFileName(ParamStr(0));
    Process1.Execute;
    Close;
    fmMain.Close;
  end
  else
  begin
    if Pos('not found', LowerCase(ResMsg)) > 0 then
      ShowMessage('There is no new version, please try again later')
    else
      ShowMessage('Error while getting the new version');
    stStatus.Caption:= 'Error';
  end;
end;

function TfmUpdate.GetNewVersion(var AFileName, Version, ResMsg: string; var NewVersion: Boolean): Boolean;
var
  http: THTTPSend;
  OS: string;
  List: TStringList;
  ServerRelease: Word;
  ServerMinor: Word;
  VerStr: string;
begin
  List:= TStringList.Create;

  OS:= Target + Arch + '-';
  try
    http:= THTTPSend.Create;

    if cxProxy.Checked then
    begin
      http.ProxyHost:= edProxy.Text;
      http.ProxyPort:= edPort.Text;
      http.ProxyUser:= edUser.Text;
      http.ProxyPass:= edPassword.Text;
    end;

    http.HTTPMethod('GET', 'http://code-sd.com/turbobird/releases/' + OS + IntToStr(Major));
    // Linux64-0
    List.LoadFromStream(http.Document);
    VerStr:= Trim(List.Text);
    ServerMinor:= StrToInt(Copy(VerStr, 1, Pos('.', VerStr) - 1));
    Delete(VerStr, 1, Pos('.', VerStr));
    ServerRelease:= StrToInt(VerStr);
    NewVersion:= (Minor < ServerMinor) or (ServerRelease > ReleaseVersion);

    Version:= IntToStr(Major) + '.' + IntToStr(ServerMinor) + '.' + IntToStr(ServerRelease);
    AFileName:= 'TurboBird-' + OS + IntToStr(Major) + '.zip';
    // TurboBird-Linux32-1.zip
    Result:= True;
    List.Free;
    http.Free

  except
  on e: exception do
  begin
    Result:= False;
    ResMsg:= e.Message;
  end;
  end;

end;

function TfmUpdate.DownloadNewVersion: Boolean;
begin
  downloadThread:= THTTPDownload.Create('http://code-sd.com/turbobird/releases/' + fNewFileName, fNewFileName);
  downloadThread.OnTerminate:= @DownloadTerminated;
  downloadThread.FreeOnTerminate:= False;
  downloadThread.Resume;
end;

procedure TfmUpdate.Init(aMajor, aMinor, aReleaseVersion: Word);
begin
  Major:= aMajor;
  Minor:= aMinor;
  ReleaseVersion:= aReleaseVersion;
end;

initialization
  {$I update.lrs}

end.

