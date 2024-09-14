unit alsa_min;

// by Fred vS | fiens@hotmail.com | 2024

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  dynlibs,
  CTypes;
  
const
  device = 'default' + #0; // name of sound device  

type
  // Signed frames quantity
  snd_pcm_sframes_t = cint;

  // PCM handle
  PPsnd_pcm_t = ^Psnd_pcm_t;
  Psnd_pcm_t  = Pointer;

  // PCM stream (direction) 
  snd_pcm_stream_t = cint;

  // PCM sample format
  snd_pcm_format_t = cint;

  // PCM access type
  snd_pcm_access_t = cint;

  // Unsigned frames quantity
  snd_pcm_uframes_t = cuint;
  
const
  // Playback stream
  SND_PCM_STREAM_PLAYBACK: snd_pcm_stream_t = 0;

  // Unsigned 8 bit
  SND_PCM_FORMAT_U8: snd_pcm_format_t       = 1;
  
  // Signed 16 bit
  {$IFDEF FPC_LITTLE_ENDIAN}
  SND_PCM_FORMAT_S16: snd_pcm_format_t       = 2;
  {$else}   
  SND_PCM_FORMAT_S16: snd_pcm_format_t       = 3; 
  {$ENDIF}    	

  // snd_pcm_readi/snd_pcm_writei access
  SND_PCM_ACCESS_RW_INTERLEAVED: snd_pcm_access_t = 3;
  
// Dynamic load : Vars that will hold our dynamically loaded ALSA methods...
var
  snd_pcm_open: function(pcm: PPsnd_pcm_t; Name: PChar; stream: snd_pcm_stream_t; mode: cint): cint; cdecl;

  snd_pcm_set_params: function(pcm: Psnd_pcm_t; format: snd_pcm_format_t; access: snd_pcm_access_t; channels, rate: cuint; soft_resample: cint; latency: cuint): cint; cdecl;

  snd_pcm_writei: function(pcm: Psnd_pcm_t; buffer: Pointer; size: snd_pcm_uframes_t): snd_pcm_sframes_t; cdecl;

  snd_pcm_recover: function(pcm: Psnd_pcm_t; err, silent: cint): cint; cdecl;

  snd_pcm_drain: function(pcm: Psnd_pcm_t): cint; cdecl;

  snd_pcm_close: function(pcm: Psnd_pcm_t): cint; cdecl;

// Special function for dynamic loading of lib ...
  as_Handle: TLibHandle = dynlibs.NilHandle; // this will hold our handle for the lib

  ReferenceCounter: integer = 0;  // Reference counter
 
  function as_Load(): Boolean;
  procedure as_Unload();
  
implementation

function as_IsLoaded: Boolean;
begin
  Result := (as_Handle <> dynlibs.NilHandle);
end;

function as_Load(): Boolean; // load the lib
var
  thelib: string = 'libasound.so.2';
begin
  Result := False;
  if as_Handle <> dynlibs.NilHandle then // is it already there ?
  begin
    Inc(ReferenceCounter);
    Result := True; 
  end
  else
  begin // go & load the library
    as_Handle := DynLibs.SafeLoadLibrary(thelib); // obtain the handle we want
    if as_Handle <> DynLibs.NilHandle then
    begin // now we tie the functions to the VARs from above

      Pointer(snd_pcm_open)       := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_open'));
      Pointer(snd_pcm_set_params) := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_set_params'));
      Pointer(snd_pcm_writei)     := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_writei'));
      Pointer(snd_pcm_recover)    := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_recover'));
      Pointer(snd_pcm_drain)      := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_drain'));
      Pointer(snd_pcm_close)      := DynLibs.GetProcedureAddress(as_Handle, PChar('snd_pcm_close'));

      Result           := as_IsLoaded;
      ReferenceCounter := 1;
    end;
  end;
end;

procedure as_Unload();
begin
   if ReferenceCounter > 0 then
    Dec(ReferenceCounter);
  if ReferenceCounter < 0 then
    Exit;
  if as_IsLoaded then
  begin
    DynLibs.UnloadLibrary(as_Handle);
    as_Handle := DynLibs.NilHandle;
  end;
end;

end.

